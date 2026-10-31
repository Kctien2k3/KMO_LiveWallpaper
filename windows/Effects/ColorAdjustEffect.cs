using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace KMO_LiveWallpaper.Effects
{
    /// <summary>
    /// Bộ lọc màu sắc phần cứng (GPU Shader Model 2.0) cho KMO Live Wallpaper trên Windows.
    /// Khắc phục hiện tượng video bị nhợt nhạt và cho phép tinh chỉnh Tương phản (Contrast) & Độ rực rỡ (Saturation).
    /// </summary>
    public class ColorAdjustEffect : ShaderEffect
    {
        private static readonly PixelShader _pixelShader;
        public static bool IsSupported { get; }

        private static readonly byte[] ShaderBytecode = new byte[]
        {
            0x00, 0x02, 0xFF, 0xFF, 0x51, 0x00, 0x00, 0x05, 0x02, 0x00, 0x0F, 0xA0, 0xD0, 0xB3, 0x59, 0x3E,
            0x59, 0x17, 0x37, 0x3F, 0x98, 0xDD, 0x93, 0x3D, 0x00, 0x00, 0x00, 0x3F, 0x5B, 0x00, 0x00, 0x02,
            0x00, 0x00, 0x00, 0x90, 0x00, 0x08, 0x0F, 0xA0, 0x5B, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x80,
            0x00, 0x00, 0x03, 0xB0, 0x42, 0x00, 0x00, 0x03, 0x00, 0x00, 0x0F, 0x80, 0x00, 0x00, 0xE4, 0xB0,
            0x00, 0x08, 0xE4, 0xA0, 0x0C, 0x00, 0x00, 0x03, 0x01, 0x00, 0x01, 0x80, 0x00, 0x00, 0xE4, 0x80,
            0x02, 0x00, 0xE4, 0xA0, 0x13, 0x00, 0x00, 0x04, 0x02, 0x00, 0x07, 0x80, 0x00, 0x00, 0x00, 0xA0,
            0x00, 0x00, 0xE4, 0x80, 0x01, 0x00, 0x00, 0x80, 0x03, 0x00, 0x00, 0x03, 0x02, 0x00, 0x07, 0x80,
            0x02, 0x00, 0xE4, 0x80, 0x02, 0x00, 0xFF, 0xA0, 0x04, 0x00, 0x10, 0x04, 0x00, 0x00, 0x07, 0x80,
            0x02, 0x00, 0xE4, 0x80, 0x01, 0x00, 0x00, 0xA0, 0x02, 0x00, 0xFF, 0xA0, 0x01, 0x00, 0x00, 0x02,
            0x00, 0x08, 0x0F, 0x80, 0x00, 0x00, 0xE4, 0x80, 0xFF, 0xFF, 0x00, 0x00
        };

        static ColorAdjustEffect()
        {
            try
            {
                _pixelShader = new PixelShader();
                using var ms = new MemoryStream(ShaderBytecode);
                _pixelShader.SetStreamSource(ms);
                IsSupported = true;
            }
            catch (Exception ex)
            {
                App.Log($"[ColorAdjustEffect] PixelShader initialization failed: {ex.Message}");
                _pixelShader = new PixelShader();
                IsSupported = false;
            }
        }

        public ColorAdjustEffect()
        {
            PixelShader = _pixelShader;

            UpdateShaderValue(InputProperty);
            UpdateShaderValue(SaturationProperty);
            UpdateShaderValue(ContrastProperty);
        }

        // Texture Sampler (s0)
        public Brush Input
        {
            get => (Brush)GetValue(InputProperty);
            set => SetValue(InputProperty, value);
        }

        public static readonly DependencyProperty InputProperty =
            RegisterPixelShaderSamplerProperty(nameof(Input), typeof(ColorAdjustEffect), 0);

        // Saturation (c0) - Default 1.0 (100%)
        public double Saturation
        {
            get => (double)GetValue(SaturationProperty);
            set => SetValue(SaturationProperty, value);
        }

        public static readonly DependencyProperty SaturationProperty =
            DependencyProperty.Register(nameof(Saturation), typeof(double), typeof(ColorAdjustEffect),
                new UIPropertyMetadata(1.0, PixelShaderConstantCallback(0)));

        // Contrast (c1) - Default 1.0 (100%)
        public double Contrast
        {
            get => (double)GetValue(ContrastProperty);
            set => SetValue(ContrastProperty, value);
        }

        public static readonly DependencyProperty ContrastProperty =
            DependencyProperty.Register(nameof(Contrast), typeof(double), typeof(ColorAdjustEffect),
                new UIPropertyMetadata(1.0, PixelShaderConstantCallback(1)));
    }
}
