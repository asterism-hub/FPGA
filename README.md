# FPGA 实时频谱显示参考设计

该项目提供一个基于 FPGA 的单通道实时频谱显示链路范例，覆盖模拟信号采集、FFT 频谱分析、幅度缓存以及 720p HDMI 输出。代码遵循用户提供的 `ipsxb_fft_spectrum_top` 接口约定，方便直接在板卡工程中复用或继续扩展。默认配置以 8 位、1024 点 FFT、74.25 MHz 像素时钟为例，能够在大于 ±3.3 V 的前端调理后对直流/交流信号进行采样并渲染频谱柱状图。

## 顶层模块

```
┌───────────────────────────────────────────────────────┐
│                 ipsxb_fft_spectrum_top                │
│                                                       │
│  ┌────────────┐   ┌─────────────┐   ┌──────────────┐ │
│  │adc_to_fft_ │   │  test2 (FFT │   │ fft_mag_store│ │
│  │axis        │──▶│   包装)     │──▶│  + dpram      │─┐│
│  └────────────┘   └─────────────┘   └──────────────┘ ││
│         ▲                 │                 │        ││
│         │                 ▼                 │        ││
│   ADC 采样缓存      fft_cfg_pulse      spectrum_renderer │
│         │                 │                 ▼        ││
│         └─────────────────┴──────────────▶ hdmi_tx   ││
└───────────────────────────────────────────────────────┘
```

- **adc_to_fft_axis**：在 ADC 时钟域采样 8 位并行数据，默认提供异步 FIFO 将样本安全搬运到系统时钟域；当 `adc_clk` 与 `i_clk` 同源时，可关闭 FIFO，直接在同一时钟下输出 `{IM, RE}` 数据与 `tvalid/tlast` 握手。
- **fft_cfg_pulse**：在系统复位释放后产生单拍配置脉冲，驱动 FFT IP 进入前向变换模式。
- **test2**：对接厂商 FFT IP（此处默认使用 `fft_ip_core_stub` 占位），完成 AXI4-Stream 数据到 IP 接口的封装，同时回传 `tready/tvalid`、`tlast` 等信号。
- **fft_mag_store**：利用 `fft_magnitude` 计算频谱幅度，并只保留正频率半谱写入双口 RAM。
- **dpram**：双口存储器，A 口在系统时钟下写入幅度，B 口在像素时钟下读取，用于视频渲染。
- **vt_720p**：产生 1280×720@60 Hz 的行场同步、Data Enable 以及当前像素坐标。
- **spectrum_renderer**：根据像素坐标读取半谱幅度，绘制绿色柱状图并叠加网格背景。
- **hdmi_tx**：简化的 TMDS 输出占位模块，在硬件工程中需替换为对应板卡的 HDMI PHY IP。

顶层模块只需输入系统时钟 `i_clk`、异步低有效复位 `i_rstn`、ADC 采样时钟 `adc_clk`、像素时钟 `pix_clk` 以及 8 位 ADC 采样数据 `adc_data`，即可在 HDMI 口输出频谱图。若 `adc_clk` 与 `i_clk` 来自同一 PLL，可通过参数将 `adc_to_fft_axis` 的异步 FIFO 关闭。

## 主要源码文件

| 文件 | 说明 |
| ---- | ---- |
| `src/adc_to_fft_axis.v` | ADC 域采样与 AXI4-Stream 桥接，内置异步 FIFO（Gray 码指针）实现跨时钟域传输。 |
| `src/ipsxb_fft_sync_arstn.v` | 异步低有效复位同步电路。 |
| `src/fft_cfg_pulse.v` | FFT 配置脉冲发生器。 |
| `src/test2.v` | FFT IP 包装，占位对接 `fft_ip_core_stub`。 |
| `src/fft_mag_store.v` | 频谱幅度计算并写入双口 RAM。 |
| `src/dpram.v` | 简单真双口 RAM，实现频谱缓存的读写解耦。 |
| `src/vt_720p.v` | 720p 行场时序发生器。 |
| `src/spectrum_renderer.v` | 频谱柱状图与网格渲染。 |
| `src/hdmi_tx.v` | HDMI 发射器占位模块，工程化时需替换为实际 TMDS 编码 IP。 |
| `src/fft_ip_core_stub.v` | FFT IP 空壳接口，待替换为厂商实现。 |
| `src/ad_clock_stub.v` | 采样时钟发生器占位模块。 |

旧版的 `adc_sampler`、`sample_buffer`、`display_formatter`、`signal_metrics` 等文件仍保留在仓库中，可作为扩展或替换实现的参考。

## 使用说明

1. **接入实际 IP**：将 `fft_ip_core_stub` 与 `hdmi_tx` 替换为器件对应的 FFT 与 TMDS 输出 IP，确保接口命名与数据宽度一致。若板卡提供现成的 HDMI IP，可直接在顶层连接。
2. **ADC 前端**：按需求设计前级放大/衰减电路，使输入范围匹配 8 位 ADC 的参考电压。若 `adc_clk` 与 `i_clk` 来自同一 PLL，可将 `adc_to_fft_axis` 的 `USE_ASYNC` 置零以关闭异步 FIFO；若存在不相关的时钟源，则保持异步 FIFO 以确保跨域可靠性。
3. **参数调整**：修改 `ipsxb_fft_spectrum_top` 的 `NPOINT`、`INPUT_WIDTH`、`MAG_W` 等参数时，需同步调整 BRAM 位宽和渲染缩放逻辑（`spectrum_renderer` 内的常量）。
4. **仿真验证**：在综合前可用行为模型驱动 `adc_data`，通过仿真观察 AXI4-Stream 链路与 RAM 写入是否符合预期，并结合波形检查 `s_tvalid/tready` 握手。
5. **硬件调试**：部署到 FPGA 后，先确认 `vt_720p` 产生正确的行场同步，再接通 FFT 数据流，最后根据实际输入调节渲染比例或加窗等算法。

## 进一步扩展

- **窗口函数**：在 `adc_to_fft_axis` 输出前加入窗系数乘法，提高频谱动态范围。
- **多通道**：复制 ADC 采样通道并增加 FFT/渲染实例，实现双通道或多路并行显示。
- **参数读出**：若需要幅值/频率/THD 等数值，可结合旧版 `signal_metrics` 模块，将其挂接在 `fft_mag_store` 输出旁边进行计算。
- **显示样式**：在 `spectrum_renderer` 内增加文字叠加、刻度线或彩色渐变，打造更直观的 UI。

该工程聚焦于最小可用的实时频谱链路，既可以直接用于教学演示，也可以作为后续深度定制的起点。
