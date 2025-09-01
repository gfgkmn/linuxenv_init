#!/usr/bin/env sh

# check_status=$(python /home/work/Application/bin/check_gpu.py)
# main_pids=$(pgrep -f dialog_websockets)

# if [ -z "$check_status"  ] && [ ! -f /home/yuhe/mail_already  ]; then
# 		mutt -s 'guokr server is down, try to auto start it' gfgkmn@foxmail.com < mail;
#         kill -9 $main_pids
#         for i in $(nvidia-smi -q --display=PIDS | grep "Process ID" | awk '{print $4}'); do kill -9 $i; done
#         cd /home/yuhe/online/xl-transformer/pytorch/model_cache/logs || exit
#         if [ ! -d /home/yuhe/online/xl-transformer/pytorch/model_cache/logs/temp ]
#         then
#             mkdir /home/yuhe/online/xl-transformer/pytorch/model_cache/logs/temp
#         fi
#         mv /home/yuhe/online/xl-transformer/pytorch/model_cache/logs/*.log /home/yuhe/online/xl-transformer/pytorch/model_cache/logs/temp
#         rm /home/yuhe/online/xl-transformer/pytorch/model_cache/logs/*.log

#         cd /home/yuhe/online/xl-transformer/pytorch || exit
#         nohup bash scripts/run_dialog_websocket.sh huakuaimix 2>&1 &
# 		touch /home/yuhe/mail_already
# fi

# PROCESS_INFO=$(pgrep --euid yuhe python | wc -l)
PROCESS_INFO=$(pgrep -f xiaomeng/continue | wc -l)
if [ "$PROCESS_INFO" -ne 9 ] && [ ! -f /home/work/Application/runflags/mail_already ]; then
    # /usr/local/bin/terminal-notifier -title '💰' -message 'predict run over'
    mutt -s 'deepspeed rl model on work-machine is done or down' gfgkmn@163.com </home/work/Application/runflags/mailtemplete
    touch /home/work/Application/runflags/mail_already
fi
