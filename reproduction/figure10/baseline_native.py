import time
import sys
import os
import zmq
from signal_pb2 import *
import subprocess
import requests
from concurrent.futures import ThreadPoolExecutor
import argparse
import queue
import multiprocessing
from multiprocessing import Process
from multiprocessing import Queue as pqueue
import logging
logging.basicConfig(format='%(asctime)s.%(msecs)03d: %(message)s', datefmt='%Y-%m-%d,%H:%M:%S', filename='router.log', filemode='w', level=logging.INFO)

# GPU id -> NUMA-local cores of a JURECA DC-GPU node; clients are pinned there.
NUMA_CORES = {0: list(range(48, 64)), 1: list(range(16, 32)),
              2: list(range(112, 128)), 3: list(range(80, 96))}
TORPOR = os.environ['TORPOR']
NATIVE_SIF = os.environ.get('NATIVE_SIF', f'{TORPOR}/images/torpor-native.sif')
# Shared by figures 8, 9 and 10: log into logs_figN of the current directory.
LOG_DIR = 'logs_' + os.path.basename(os.getcwd()).replace('figure', 'fig')
os.makedirs(LOG_DIR, exist_ok=True)
# Client endpoints listen on CLIENT_PORT_BASE + client_id. Upstream uses 9000,
# which puts client 100 on port 9100, taken by node_exporter on JURECA nodes.
CLIENT_PORT_BASE = int(os.environ.get('CLIENT_PORT_BASE', 20000))

CLIENT_SIF = os.environ.get('CLIENT_SIF',
    f'{TORPOR}/images/torpor-client.sif')
# Seconds a function is skipped after a request timeout. Upstream skips it for
# the rest of the run.
UNHEALTHY_COOLDOWN = 10

class SocketCache():
    def __init__(self, context):
        self.context = context
        self.socket_cache = {}

    def get(self, addr, typ=zmq.REQ):
        if addr in self.socket_cache:
            return self.socket_cache[addr]
        else:
            socket = self.context.socket(typ)
            socket.connect(addr)
            self.socket_cache[addr] = socket
            return socket

model_mixed = ['resnet50', 'resnet101', 'resnet152', 'densenet169', 'densenet201', 'inception', 'efficientnet', 'bertqa']
def get_mixed_model_name(client_id):
    model_idx = client_id % len(model_mixed)
    return model_mixed[model_idx]

def get_mixed_model_level(client_id):
    model_idx = client_id % len(model_mixed)
    if model_idx < 3:
        return 1
    elif model_idx < 7 and model_idx >= 3:
        return 0
    elif model_idx == 7:
        return 2
    return 1

def get_manager_ipc(manager_id):
    return 'ipc:///dev/shm/ipc/manager_' + str(manager_id)

def get_server_id(client_id):
    return client_id % server_num

def container_manager(server_id):
    global bert_function
    logging.info(f'Start manager {server_id}')

    context = zmq.Context(1)
    manager_puller = context.socket(zmq.PULL)
    manager_puller.bind(get_manager_ipc(server_id))

    router_pusher = context.socket(zmq.PUSH)
    router_pusher.connect(f'ipc:///dev/shm/ipc/router')

    poller = zmq.Poller()
    poller.register(manager_puller, zmq.POLLIN)

    while True:
        socks = dict(poller.poll(timeout=1))

        if manager_puller in socks and socks[manager_puller] == zmq.POLLIN:
            obj = manager_puller.recv_pyobj()
            flag, msg = obj
            if flag == '0': # load
                pass
            elif flag == '1': # execute
                func_id, issue_t, arrival_t = msg
                
                # logging.info(f'Handle request {func_id}')
                start_t = time.time()
                try:
                    x = requests.get('http://localhost:' + str(CLIENT_PORT_BASE + func_id), headers={"cur_server" : str(server_id), "batch_size" : str(len(arrival_t))}, timeout=5)
                except Exception as e:
                    logging.info(f'Func {func_id} on server {server_id} timeout')
                    router_pusher.send_pyobj(('2', func_id))
                else:
                    end_t = time.time()
                    for arr in arrival_t:
                        logging.info(f'Func {func_id} batch size {len(arrival_t)} on server {server_id} end-to-end time: {end_t - arr}, issue: {end_t - issue_t}, query: {end_t - start_t}, resp: {x.text}')
                    router_pusher.send_pyobj(('1', (func_id, [end_t - arr for arr in arrival_t])))

class Router():
    def __init__(self, server_num, func_num):
        self.context = zmq.Context(1)

        self.service_socket = self.context.socket(zmq.PULL)
        self.service_socket.bind('ipc:///dev/shm/ipc/externel_service')

        self.router_socket = self.context.socket(zmq.PULL)
        self.router_socket.bind('ipc:///dev/shm/ipc/router')

        self.server_num = server_num
        self.func_num = func_num
        # launch_batch = [ (i % server_num, i) for i in range(func_num)]

        MAX_CONTAINERS = 72
        actual_func_num = min(func_num, MAX_CONTAINERS)
        launch_batch = [ (i % server_num, i) for i in range(actual_func_num)]
        self.func_num = actual_func_num

        # for server_id, model_id in launch_batch:
            # os.system(f'docker run --gpus \'"device={server_id}"\' --cpus=1 -e OMP_NUM_THREADS=1 -e KMP_DUPLICATE_LIB_OK=TRUE -e model_name={model_name} --rm  --name client-{model_id}  --network=host --ipc=host standalone-native python endpoint.py {9000 + model_id} &')

        batch_size = 10
        for i in range(0, len(launch_batch), batch_size):
            batch = launch_batch[i:i+batch_size]
            for server_id, model_id in batch:
                self._launch_native_endpoint(server_id, model_id)
            logging.info(f'Launched batch {i // batch_size + 1}, waiting 5 seconds...')
            time.sleep(5)

        # Poll each endpoint until ready and relaunch it if its process died:
        # under concurrent launches, apptainer --nv occasionally fails CUDA init.
        for server_id, model_id in launch_batch:
            self._wait_for_endpoint(server_id, model_id)

        self.func_stat = {i: [0, 0, 0] for i in range(func_num)}
        self.func_avail = {i: True for i in range(func_num)}

        self.schedule_queue = queue.Queue()
        self.pool = ThreadPoolExecutor(max_workers=2)
        self.sockets = SocketCache(self.context)

        self.timeout_func = {}  # func_id -> timestamp it was last marked unhealthy
        for i in range(server_num):
            reader_p = Process(target=container_manager, args=(i,))
            reader_p.start()
        logging.info('Start schedule')

    def _launch_native_endpoint(self, server_id, model_id):
        # spread this GPU's endpoints over all 16 of its NUMA-local cores
        core = NUMA_CORES[server_id][(model_id // self.server_num) % 16]
        os.system(
            f'taskset -c {core} apptainer exec --nv '
            f'--env CUDA_VISIBLE_DEVICES={server_id},OMP_NUM_THREADS=1,KMP_DUPLICATE_LIB_OK=TRUE,model_name={model_name} '
            f'--pwd / '
            f'{NATIVE_SIF} python endpoint.py {CLIENT_PORT_BASE + model_id} '
            f'> {LOG_DIR}/native_{model_id}.log 2>&1 &'
        )

    def _is_endpoint_process_alive(self, model_id):
        return os.system(f'pgrep -f "endpoint.py {CLIENT_PORT_BASE + model_id}\\$" > /dev/null 2>&1') == 0

    def _wait_for_endpoint(self, server_id, model_id, max_relaunches=5):
        # endpoint.py has no health check; its handler runs a real forward pass,
        # and the first one after a cold start is slow. Relaunch only if the
        # process died, or if it stays unresponsive for all polls (hung).
        relaunches = 0
        while True:
            died = False
            for attempt in range(6):
                try:
                    x = requests.get('http://localhost:' + str(CLIENT_PORT_BASE + model_id), timeout=15)
                except Exception:
                    if not self._is_endpoint_process_alive(model_id):
                        died = True
                        break
                    time.sleep(2)
                else:
                    return
            relaunches += 1
            if relaunches > max_relaunches:
                logging.error(f'Endpoint {model_id} on server {server_id} still not up after {relaunches} relaunches, giving up')
                return
            reason = 'process died' if died else 'still not responding after being alive'
            logging.warning(f'Endpoint {model_id} on server {server_id} not up ({reason}), relaunching (attempt {relaunches})')
            os.system(f'pkill -KILL -f "endpoint.py {CLIENT_PORT_BASE + model_id}$" 2>/dev/null')
            self._launch_native_endpoint(server_id, model_id)
            time.sleep(5)

    def baseline_schedule(self):
        req_queue = []
        def has_req():
            return len(req_queue) > 0
        
        def insert_req(f, arr):
            req_queue.append((f, arr))
        
        def get_req(out=True):
            if out:
                return req_queue.pop(0)
            else:
                return req_queue[0] if len(req_queue) > 0 else None

        def batch_check(f):
            req = get_req(False)
            if req is None or req[0] != f:
                return False
            return True

        logging.info('Listen on schedule queue using FIFO policy')

        while True:                
            try:
                sched_typ, sched_msg = self.schedule_queue.get(timeout=0.001)
            except queue.Empty:
                if has_req():
                    req = get_req()
                    if req is None:
                        continue
                    
                    f, arr = req
                    # batching
                    arrs = [arr]
                    while batch_check(f) and len(arrs) < batch_size_limit:
                        f, arr = get_req()
                        arrs.append(arr)

                    issue_t = time.time()
                    self.func_avail[f] = False
                    self.sockets.get(get_manager_ipc(get_server_id(f)), zmq.PUSH).send_pyobj(('1', (f, issue_t, arrs)))

            else:
                if sched_typ == 0: # requests
                    target_func, arr_t = sched_msg
                    insert_req(target_func, arr_t)
                    logging.info(f'Inserted request {target_func}, cur_len: {len(req_queue)}')
                elif sched_typ == 1: # update queue
                    count = len([f for f, stat in self.func_stat.items() if stat[1] > 0])
                    if count <= 0:
                        continue

                    slo_ratio = len([f for f, stat in self.func_stat.items() if stat[1] > 0 and stat[0] / stat[1] >= slo_percentile]) / count
                    logging.info(f'FIFO update. slo_ratio: {slo_ratio}, queued_req: {len(req_queue)}')
    
    def run(self):
        self.pool.submit(self.poll_exterel)
        self.baseline_schedule()

    def poll_exterel(self):

        poller = zmq.Poller()
        poller.register(self.service_socket, zmq.POLLIN)
        poller.register(self.router_socket, zmq.POLLIN)
        
        start_t = time.time()
        end_t = time.time()
        while True:
            socks = dict(poller.poll(timeout=1))
            
            if self.service_socket in socks and socks[self.service_socket] == zmq.POLLIN:
                target_func = int(self.service_socket.recv())
                if target_func >= 0:
                    cur_t = time.time()
                    # logging.info(f'Get request {target_func} at {cur_t}')
                    if target_func in self.timeout_func and cur_t - self.timeout_func[target_func] < UNHEALTHY_COOLDOWN:
                        logging.info(f'Ignore unhealthy func {target_func}')
                    else:
                        self.timeout_func.pop(target_func, None)
                        self.schedule_queue.put((0, (target_func, cur_t)))
                elif target_func == -1:
                    # clear up and warm up
                    clear_start_t = time.time()

                    for i in range(self.func_num):
                        x = requests.get('http://localhost:' + str(CLIENT_PORT_BASE + i), timeout=5)
                        print(x.text)

                    logging.info(f'Clear up and warm up done, time: {time.time() - clear_start_t}')


            if self.router_socket in socks and socks[self.router_socket] == zmq.POLLIN:
                obj = self.router_socket.recv_pyobj()
                flag, sched_msg = obj

                if flag == '0':
                    pass

                elif flag == '1':
                    func_id, lats = sched_msg
                    for lat in lats:
                        self.func_stat[func_id][2] += lat
                        self.func_stat[func_id][1] += 1
                        self.func_stat[func_id][0] = self.func_stat[func_id][0] + 1 if lat <= latency_ddl else self.func_stat[func_id][0]
                    self.func_avail[func_id] = True
                
                elif flag == '2':
                    func_id = sched_msg
                    self.timeout_func[func_id] = time.time()
            
            end_t = time.time()
            if end_t - start_t > 2: # adjust request queue
                start_t = end_t
                self.schedule_queue.put((1, None))

parser = argparse.ArgumentParser()
parser.add_argument('-m', type=str, default='resnet152')    # Model name
parser.add_argument('-s', type=int, default=1)  # GPU number
parser.add_argument('-f', type=int, default=1)  # Function number
parser.add_argument('-t', type=int, default=98)
parser.add_argument('-d', type=int, default=100)
parser.add_argument('-b', type=int, default=1)

args = parser.parse_args()

model_name = args.m
server_num = args.s
func_num = args.f
slo_percentile = args.t / 100
latency_ddl = args.d / 1000
batch_size_limit = args.b

router = Router(server_num, func_num)
router.run()
