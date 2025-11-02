# FPGA 信号频谱分析系统

本工程提供一个基于 FPGA 的实时信号采集与频谱分析参考设计，覆盖从模拟信号采集、FFT 频谱处理到可视化显示以及关键参数测量的完整链路。设计以 8~12 位、500 kSPS 以上的串行 ADC 为目标，FFT 规模默认为 1024 点，可在 OLED/LCD/HDMI 等视频接口上输出频谱图，同时实时给出幅值、频率、占空比和 THD（前 5 次谐波）指标。

## 顶层结构

```
┌────────────────────────────────────────────────────────┐
│                    spectrum_analyzer_top               │
│                                                        │
│  ┌──────────┐    ┌────────────┐    ┌────────────┐      │
│  │adc_sampler│──▶│sample_buffer│──▶│fft_engine   │────┐ │
│  └──────────┘    └────────────┘    │wrapper     │    │ │
│                                     └────────────┘    │ │
│                                          │             │ │
│                                          ▼             │ │
│                                   ┌────────────┐       │ │
│                                   │fft_magnitude│──────┼─┤
│                                   └────────────┘      │ │
│                                          │             │ │
│                                          ▼             │ │
│                              ┌────────────────────┐    │ │
│                              │signal_metrics      │    │ │
│                              └────────────────────┘    │ │
│                                          │             │ │
│                                          ▼             │ │
│                              ┌────────────────────┐    │ │
│                              │display_formatter   │◀───┘ │
│                              └────────────────────┘      │
└────────────────────────────────────────────────────────┘
```

- **adc_sampler**：以可配置 SCLK 分频驱动串行 ADC，完成连续采样并输出带帧起始标志的数据流。
- **sample_buffer**：双缓冲结构缓存整帧采样（默认 1024 点），与 FFT 引擎通过 AXI-Stream 式握手机制完成帧切换。
- **fft_engine_wrapper**：对接厂商提供的 FFT IP Core（需替换 `fft_ip_core_stub`），完成频域变换并输出频谱数据及 bin 索引。
- **fft_magnitude**：对复数频谱计算近似幅度，供后续显示与参数运算使用。
- **signal_metrics**：在时域计算幅值、频率（基于零点捕获）、占空比，并在频域缓存半谱数据后计算 THD（前五次谐波平方和 / 基波平方）。
- **display_formatter**：实现 640×480（可调）视频输出，将频谱绘制为绿色柱状图，同时在屏幕顶部 4 行字符区域显示幅值、频率（Hz）、占空比和 THD 百分比。

## IP Core 接入

文件 `src/fft_ip_core_stub.v` 给出了厂商 FFT IP 的空壳接口，实际工程中请将其替换为对应器件生成的 IP 模块，保持 AXI-Stream 接口信号名称一致即可。

## 视频接口

`display_formatter` 输出 RGB565 像素与 `pixel_ready` 握手信号，可直接对接 HDMI/VGA/LCD 控制器的坐标扫描逻辑。若目标分辨率与本例不同，可通过参数 `H_RES`、`V_RES` 调整绘图区域。

## 模块参数与扩展

- `ADC_WIDTH`、`SAMPLE_RATE` 等参数可根据 ADC 精度和采样率修改。
- FFT 点数通过 `FFT_POINTS` 参数设定，需同步调整 `sample_buffer`、`signal_metrics`、`display_formatter` 等模块。
- 若需双通道采样，可复制 `adc_sampler` 与 `sample_buffer`，在顶层增加多路 FFT 或时分复用逻辑。

## 时序与资源说明

- 双缓冲采样和 FFT 数据流使用全同步逻辑，避免读写冲突。
- THD 计算在频谱数据写入 RAM 后分两个阶段（寻找基波 + 谐波累加）完成，对资源需求较小。
- 数字字符渲染采用 5×7 点阵，保证在小分辨率下的可读性。

## 目录结构

```
src/
 ├─ adc_sampler.v          // 串行 ADC 采集接口
 ├─ sample_buffer.v        // 采样数据双缓冲
 ├─ fft_ip_core_stub.v     // FFT IP 占位模块
 ├─ fft_engine_wrapper.v   // FFT IP AXI-Stream 封装
 ├─ fft_magnitude.v        // 频谱幅值估算
 ├─ signal_metrics.v       // 幅值/频率/占空比/THD 计算
 ├─ display_formatter.v    // 频谱图与字符叠加
 └─ spectrum_analyzer_top.v// 顶层系统整合
```

## 快速验证建议

1. 使用仿真激励替换 `adc_dout`，构造已知频率与占空比的信号，验证时域指标与显示数值。
2. 在综合实现前，将 `fft_ip_core_stub` 替换为真实 FFT IP，并确认其数据宽度和定标参数。
3. 若连接 HDMI/VGA 控制器，确保扫描时序提供 `pixel_x`/`pixel_y`/`pixel_valid` 与 `pixel_ready` 的握手逻辑。

该工程提供完整的骨架代码，可根据具体硬件进行适配与扩展。欢迎在此基础上加入噪声抑制、窗函数、自动量程等高级功能。
