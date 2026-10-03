# AXI-Lite 到 APB 桥接器 UVM 验证项目

我基于 axi4_lite_slave、apb_master 和 axilite2apb 三个 RTL 文件搭建了模块级验证平台。AXI 端发起读写，APB 端提供从设备响应，再检查桥接后的地址、数据、选通和错误返回。

我先搭建 UVM 组件并编写 20 组定向用例，随后补充了 8 组随机、边界、长等待和异常复位测试。目前共 28 组用例，配套 10 条 SVA 断言、Makefile 和回归脚本。工程按 VCS MX O-2018.09-1、UVM 1.2 和 Verdi 配置，默认数据宽度 32 位、ID 宽度 4 位，时钟周期 20 ns。

## 平台实现

我用两个 agent 完成总线两侧的驱动和采集。AXI agent 包含 sequencer、driver 和 monitor，负责发送 AW/W/AR、控制 BREADY/RREADY，并记录五个通道的实际握手。APB agent 包含响应 driver 和 monitor，根据 DUT 发出的访问返回 PREADY、PRDATA、PSLVERR；这个 driver 直接观察总线，因此没有配置 APB sequencer。

所有激励和采集记录复用 x2p_transaction。测试放在一个 x2p_directed_sequence 中，由一个 x2p_test 启动，通过 CASE 选择测试组。env 创建两个 agent、reference model、scoreboard 和四个 FIFO。

| 主要文件 | 内容 |
| --- | --- |
| rtl/ 下的三个 .v 文件 | 原始桥接器 RTL，保留原文件内容 |
| tb/x2p_interface.sv | 总线信号和 clocking block |
| tb/x2p_transaction.sv、x2p_config.sv | 事务字段、随机约束、平台配置和 vif 类型 |
| tb/x2p_axi_sequencer.sv、x2p_axi_driver.sv、x2p_axi_monitor.sv、x2p_axi_agent.sv | AXI 端的发送、握手采集和组件封装 |
| tb/x2p_apb_driver.sv、x2p_apb_monitor.sv、x2p_apb_agent.sv | APB 从设备响应、存储和访问采集 |
| tb/x2p_refmodel.sv、x2p_scoreboard.sv、x2p_env.sv | 结果预测、比较、数量检查和 FIFO 连接 |
| tb/x2p_directed_sequence.sv、x2p_test.sv | 28 组测试的激励与启动入口 |
| tb/x2p_pkg.sv、x2p_tb.sv、x2p_defs.svh | 包依赖、DUT 实例化、vif 绑定、时钟和统一 ID 位宽 |
| sva/x2p_sva.sv | 断言、cover property 和 bind |
| sim/、scripts/ | Makefile、filelist、日志检查和回归脚本 |

我把 monitor 的端口封装在各自 agent 内部，env 通过 agent 公开端口连接。数据传递使用 blocking put/get 端口和 uvm_tlm_fifo：

| 发送端 | FIFO | 接收端 |
| --- | --- | --- |
| axi_age.req_port | axi_req_fifo | refm.axi_req_get |
| apb_age.done_port | apb_done_fifo | refm.apb_done_get |
| refm.exp_port | exp_fifo | scor.exp_get |
| axi_age.rsp_port | act_fifo | scor.act_get |

FIFO 的深度设为 0，表示容量不设上限，空队列的 get 会等待。monitor 每次发送独立对象。refm 和 scoreboard 分别接收、缓存各自的输入，读写各自排队，用 epoch、方向和 ordinal 配对，ID 则作为比较字段。

## 数据和错误检查

我在 APB driver 中建立了 64 个 32 位寄存器，基地址范围为 0x00..0xFC，复位后清零。写入按 PSTRB 更新字节，读取返回完整 32 位寄存器。0xE0 的写访问、0xE4 的读访问，以及范围外或未对齐的 APB 地址返回 PSLVERR；错误写不改变存储，错误读返回 0xBAD00BAD。

地址范围和错误规则由这个从设备模型定义，桥接器负责转发访问并回传结果。当前 RTL 将 AXI 地址低两位清零，直接传递 WDATA/WSTRB。SIZE=0/1/2 可以访问，SIZE=3..7 在桥接器本地返回 SLVERR，且不产生 APB 访问；本地错误读返回 0。

reference model 另有一份寄存器存储。我用原始 AXI 请求计算期望地址、字节更新和响应，再核对实际 APB 访问。成功写按 APB 完成顺序更新参考存储，随后由 scoreboard 比较 AXI 返回的 RESP、ID 和读数据。

复位由 AXI driver 统一驱动。每次复位递增 epoch，清空 FIFO、半笔 AW/W、待响应请求和待比较记录，两份寄存器存储也清零。取消的事务单独计为 ABORTED。复位后发出的新请求使用新的 epoch，避免前后记录混在一起。

## 测试用例

前 20 组用例先把基本功能和通道时序逐项拆开：

| 编号 | 测试内容 |
| --- | --- |
| TC01 | 初始和空闲复位，读取清零值 |
| TC02 | 单次完整写入、读回 |
| TC03 | AW 比 W 提前 3 拍 |
| TC04 | W 比 AW 提前 3 拍 |
| TC05 | AW/W 同拍，8 个地址连续写读 |
| TC06 | 全部 16 种 WSTRB，包含零选通 |
| TC07 | 字节、半字访问和地址对齐 |
| TC08 | 首尾地址、窄读地址和高位非法地址 |
| TC09 | APB 等待 0/1/3/8 拍 |
| TC10 | PROT=000/010 透传 |
| TC11 | BREADY 反压 3/8 拍 |
| TC12 | RREADY 反压 3/8 拍 |
| TC13 | 固定读写错误，检查错误写后的存储 |
| TC14 | 0x100 非法地址返回 SLVERR |
| TC15 | SIZE=3..7 的本地拒绝 |
| TC16 | 全部 4 位 ID，带响应反压 |
| TC17 | 读写并发，两种仲裁优先状态和不同反压 |
| TC18 | 只收到 AW 或 W 时复位 |
| TC19 | APB SETUP、ACCESS 等待中复位 |
| TC20 | B/R 响应反压期间复位 |

之后我增加了 TC21–TC28，把随机数据、边界和多种延迟组合放到同一套检查流程中：

| 编号 | 测试内容 |
| --- | --- |
| TC21 | 8 种数据模式，在两个地址写入原值和反值，再分别读回 |
| TC22 | 默认 64 次约束随机访问，随机方向、地址、ID、数据、SIZE、STRB 和延迟；每个随机写追加完整字读回 |
| TC23 | 首尾寄存器的字节、半字访问，再做 32 次约束随机边界写和读回 |
| TC24 | BREADY/RREADY 延迟 0/1/7/15 拍的全部 16 种组合 |
| TC25 | PREADY 等待 0/1/7/15/31 拍，以及双向长等待 |
| TC26 | 5 个非法地址；错误后读回合法地址，检查地址别名和存储是否受影响 |
| TC27 | 双向 PSLVERR、正常与错误访问混合、延迟错误响应及恢复读写 |
| TC28 | 六个阶段各重复复位，覆盖 1 拍和 8 拍脉宽、随机脉宽和复位后的恢复 |

随机约束写在 transaction 中。字访问按 4 字节对齐，半字按 2 字节对齐；字节和半字写的 STRB 对应实际通道，PROT 取 000/010。TC22 的随机地址限定在 0x00..0xC0。TC23 关闭 soft 默认集合，单独指定边界地址和等待集合，让 0xFD..0xFF 也能被随机选中。

当前 DUT 每个方向只有一个待处理槽，同方向连续访问在上一响应完成后继续发起，读写两个方向可以并行。各用例的激励写在同一个 sequence 的 task 中。

## 时序、断言和回归

我在下降沿通过 clocking block 驱动 AXI 请求和 APB 响应，在上升沿使用 input #1step 采样握手。AW/W 分开发送。b_delay/r_delay 表示看到 VALID 后实际保持 READY=0 的拍数，0 表示预先拉高 READY；APB 等待只统计 ACCESS 中 PREADY=0 的拍数。

scoreboard 核对实际 B/R 反压数量，refm 核对 APB 等待数量。monitor 还检查当前单槽 DUT 在 B/R 反压时对应请求 READY 保持低，并在每个复位采样拍检查 READY、VALID、PSEL、PENABLE 清零。

10 条 SVA 主要检查复位输出、APB 阶段转换与等待期间的信号保持、AXI 响应反压保持，以及 APB 结果到 AXI 响应的映射。另外有 10 条 cover property，记录相关场景是否触发。功能覆盖放在现有组件中，记录读写、地址、SIZE、STRB、RESP、ID、PROT、通道次序、等待、反压和复位。

我用 Makefile 统一编译、仿真和波形入口，回归脚本按 CASE 启动测试，保存各组日志和 CSV 汇总。日志检查同时读取 UVM 错误、scoreboard 结果、SVA 失败和超时信息。每笔事务设置 256 拍超时，顶层设置 1 ms 超时；结束时还检查 FIFO 和待处理队列是否清空。

## 运行方式

编译从 sim/ 目录开始。组件已经由 x2p_pkg.sv 按顺序 include，filelist 只列包、接口、顶层、RTL 和 SVA。

    cd x2p_uvm/sim
    make smoke                                  # 先运行 TC02
    make run                                    # 按顺序运行全部 28 组
    make added                                  # 只运行 TC21–TC28
    make run CASE=22 SEED=101 RANDOM_ITERS=128    # 指定随机配置
    make regress                                # 28 组分别仿真
    make regress_new SEED=101                    # 新增 8 组分别仿真

SEED 默认 1，RANDOM_ITERS 默认 64，允许 1..256。相同命令、配置和种子用于复现随机测试。回归日志放在 regress/ 或 regress_new/，summary.csv 记录种子、随机次数和检查结果；脚本使用 Python 3.7 及以上版本。

默认波形为 x2p.vcd。生成 FSDB 时，我需要先把 VERDI_HOME 设为自己的安装路径：

    export VERDI_HOME=/实际的/Verdi安装目录
    make clean
    make run FSDB=1 CASE=2
    make verdi

Makefile 使用 share/PLI/VCS/LINUX64/ 下的 novas.tab 和 pli.a，安装路径不同则修改这两处。Verdi 读取 simv.daidir 和波形；查看 VCD 可用 make verdi WAVE=x2p.vcd。

保存覆盖数据库使用 make run COV=1。修改 ID_WIDTH、FSDB 或 COV 后先 make clean，再重新编译。接口、DUT、transaction 和 vif 类型统一使用 X2P_ID_WIDTH。

