import time
import sys
import os
import zmq
import numpy as np

context = zmq.Context(1)
sender_socket = context.socket(zmq.PUSH)
sender_socket.connect('ipc:///dev/shm/ipc/externel_service')
data_path = '../../tools'

class Sender:
    def __init__(self, func_num, mins, fixed_rpm):
        self.func_num = func_num
        # The cache key includes the rate. Upstream keys only on func_num and mins,
        # so runs with the same func_num but a different rate replay a stale trace.
        trace_file = f'{data_path}/req_arrivals_{func_num}_{mins}min_{fixed_rpm}rpm.npy'
        if os.path.isfile(trace_file):
            self.req_arrivals = np.load(trace_file)
        else:
            # fixed per-function rate (Figure 8 uses no Azure-trace sampling)
            self.func_rate = [fixed_rpm] * func_num

            self.req_arrivals = []
            self.gen_req_arrivals(self.req_arrivals, mins = mins)

            with open(trace_file, 'wb') as f:
                np.save(f, self.req_arrivals)
        print(f'Generated {len(self.req_arrivals)} requests in {mins} mins at {fixed_rpm} rpm/func')

    def send(self, func):
        sender_socket.send_string(str(func))
        # print(f'Send func {func}')

    def gen_req_arrivals(self, req_arrivals, mins = 5):
        cur_stmp = 0
        overall_rate = int(sum(self.func_rate))

        for _ in range(mins):
            intervals = np.random.poisson(60 * 1000 / overall_rate, overall_rate)
            funcs = np.random.choice(len(self.func_rate), overall_rate, p = [r / sum(self.func_rate) for r in self.func_rate])

            for i, f in zip(intervals, funcs):
                cur_stmp += i / 1000
                req_arrivals.append((i / 1000, f))


    def run(self, flag=0):
        if flag == -1:
            # load
            self.send(-2)
        else:
            if flag == 0: # warmup
                self.send(-1)
                print(f'Warmup and sleep {0.05 * func_num + 5} sec')
                time.sleep(0.05 * func_num + 5)

            print('Start sending requests')
            for i, f in self.req_arrivals:
                func = int(f)
                # print(f'Send func {func} after sleep {i}')
                time.sleep(i)
                self.send(func)

def test(concurrency):
    for i in range(concurrency):
        sender_socket.send_string(str(i))
        sender_socket.send_string(str(i))

if __name__ == '__main__':

    func_num = 1
    if (len(sys.argv) > 1):
        func_num = int(sys.argv[1])

    mins = 5
    if (len(sys.argv) > 2):
        mins = int(sys.argv[2])

    flag = 0
    if (len(sys.argv) > 3):
        flag = int(sys.argv[3])

    fixed_rpm = 80
    if (len(sys.argv) > 4):
        fixed_rpm = int(sys.argv[4])

    sender = Sender(func_num, mins, fixed_rpm)
    sender.run(flag)
