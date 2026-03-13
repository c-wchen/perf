## cmd_perf.sh使用

cmd_perf.sh <命令集中命令名称>

cmd_perf.sh DD_DIRECT_WR_1MBS_1024CNT


## attach_perf.sh使用

在脚本中修改custom_pid指向的进程号


## gen_html.sh使用

gen_html.sh <生成perf的目录，注意perf文件的后缀是.perf.data>

gen_html.sh 20241026-11

## perf-tools

https://github.com/brendangregg/perf-tools


## ftrace-tools

./func_graph_ftrace.sh '__sys_connect' /usr/bin/curl http://www.google.com


## trace-cmd

yum install trace-cmd

trace-cmd record -p function_graph -g __sys_connect curl -XGET http://www.baidu.com

trace-cmd report



### 概念
trace-cmd 是对 Linux 内核 ftrace 接口的完整封装。它的核心逻辑是：配置过滤器 -> 启动追踪 -> 收集数据到文件 -> 解析显示。

以下是 trace-cmd 的全指令深度解析，按功能逻辑分类：

1. 核心操作三部曲 (最常用)

record：记录追踪数据
这是最常用的命令，它会产生一个 trace.dat 二进制文件。

-p (tracer): 指定追踪器，如 function, function_graph, blk (块设备)。

-e (event): 指定事件，如 sched_switch, kmem:kmalloc。

-g (graph-function): 仅在 function_graph 下使用，指定要展开调用树的入口函数。

-l (filter): 限制只追踪哪些函数（支持通配符 vfs_*）。

-P (pid): 只追踪特定进程 ID。

-F (filter-task): 只追踪由 trace-cmd 后面接的那个命令所产生的任务。

report：解析并查看数据
读取 trace.dat 并将其转换为人类可读的文本。

-i: 指定输入文件（默认是 trace.dat）。

-f: 显示所有已定义的函数。

-P: 配合 grep 使用时，可以只显示特定进程的报告。

reset：清理环境
如果追踪意外中断，内核的 ftrace 可能会保持开启状态（占用性能）。

使用 trace-cmd reset 关掉所有追踪器，清空过滤器，释放缓冲区。

2. 进阶功能命令
list：查询可用资源
不知道你的内核支持哪些事件或函数？用这个查询：

trace-cmd list -e: 列出所有可用的事件。

trace-cmd list -f: 列出所有可被追踪的内核函数。

trace-cmd list -p: 列出当前可用的追踪器。

profile：实时统计分析
类似于 top 的交互感，它不会记录详细流水账，而是统计函数调用的次数和开销。

trace-cmd profile -F ls: 运行 ls 并统计期间所有内核函数的调用频率和耗时。

stack：开启栈追踪
如果你想知道某个内核函数是谁调用的：

trace-cmd stack: 开启内核栈记录，通常配合 record -p function 使用。


# trace-cmd生成火焰图

```bash
./fg2flame.sh record -d 10 -o out.svg

./fg2flame.sh record -d 5 -p 1234 -f "vfs_read vfs_write" -o out.svg

./fg2flame.sh record -d 5 -- myprogram --args

./fg2flame.sh convert -i trace.dat -o out.svg

./fg2flame.sh report  -i trace.dat > report.txt
```