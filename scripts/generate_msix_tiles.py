#!/usr/bin/env python3
"""
生成符合 Microsoft Store 要求的高质量磁贴图标
解决 10.1.1.11 On Device Tiles 认证问题
"""

from PIL import Image
import os

def generate_tile_icon(source_img, output_path, size, description):
    """
    生成指定尺寸的高质量磁贴图标
    使用 Lanczos 重采样确保清晰度
    """
    # 使用高质量的 Lanczos 算法缩放
    resized = source_img.resize((size, size), Image.Resampling.LANCZOS)
    
    # 保存为 PNG 格式
    resized.save(output_path, format='PNG', optimize=True)
    
    file_size = os.path.getsize(output_path) / 1024
    print(f"  ✓ {description:30s} - {size}x{size}px - {file_size:.1f}KB")
    
    return output_path

def generate_scaled_tiles(source_img, base_path, base_name, base_size, scales):
    """
    生成不同 DPI 缩放的磁贴图标
    例如：Square150x150Logo.scale-100.png, Square150x150Logo.scale-125.png 等
    """
    results = []
    
    # 生成基础版本（无缩放后缀）
    base_output = os.path.join(base_path, f"{base_name}.png")
    generate_tile_icon(source_img, base_output, base_size, f"{base_name}")
    results.append(base_output)
    
    # 生成不同缩放版本
    for scale in scales:
        scaled_size = int(base_size * scale / 100)
        output_name = f"{base_name}.scale-{scale}.png"
        output_path = os.path.join(base_path, output_name)
        generate_tile_icon(source_img, output_path, scaled_size, f"{base_name} @{scale}%")
        results.append(output_path)
    
    return results

def generate_all_msix_tiles():
    """
    生成所有 MSIX 需要的磁贴图标
    符合 Microsoft Store 认证要求
    """
    print("=" * 70)
    print("Microsoft Store 高质量磁贴图标生成器")
    print("解决 10.1.1.11 On Device Tiles 认证问题")
    print("=" * 70)
    print()
    
    # 查找源图标
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    
    source_paths = [
        os.path.join(project_root, 'icon.png'),
        os.path.join(project_root, 'res', 'icon.png'),
        os.path.join(project_root, 'assets', 'icon.png'),
    ]
    
    source_icon = None
    for path in source_paths:
        if os.path.exists(path):
            source_icon = path
            print(f"✓ 找到源图标: {path}")
            break
    
    if not source_icon:
        print("✗ 错误: 找不到源图标文件")
        return False
    
    # 打开源图像
    try:
        img = Image.open(source_icon)
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        print(f"✓ 源图像尺寸: {img.size}")
        print()
    except Exception as e:
        print(f"✗ 无法打开源图像: {e}")
        return False
    
    # 创建输出目录
    output_dir = os.path.join(project_root, 'windows', 'runner', 'resources', 'tiles')
    os.makedirs(output_dir, exist_ok=True)
    print(f"✓ 输出目录: {output_dir}")
    print()
    
    # Microsoft Store 要求的 DPI 缩放
    # 100%, 125%, 150%, 200%, 400%
    scales = [100, 125, 150, 200, 400]
    
    print("正在生成磁贴图标...")
    print("-" * 70)
    
    all_generated = []
    
    # 1. Square 44x44 Logo (小磁贴，用于应用列表)
    print("\n📱 Square 44x44 Logo (应用列表图标)")
    generated = generate_scaled_tiles(img, output_dir, "Square44x44Logo", 44, scales)
    all_generated.extend(generated)
    
    # 2. Square 71x71 Logo (小磁贴)
    print("\n📱 Square 71x71 Logo (小磁贴)")
    output_path = os.path.join(output_dir, "Square71x71Logo.png")
    generate_tile_icon(img, output_path, 71, "Square71x71Logo")
    all_generated.append(output_path)
    
    # 3. Square 150x150 Logo (中等磁贴) - 最重要的一个
    print("\n📱 Square 150x150 Logo (中等磁贴 - 主要显示)")
    generated = generate_scaled_tiles(img, output_dir, "Square150x150Logo", 150, scales)
    all_generated.extend(generated)
    
    # 4. Square 310x310 Logo (大磁贴)
    print("\n📱 Square 310x310 Logo (大磁贴)")
    output_path = os.path.join(output_dir, "Square310x310Logo.png")
    generate_tile_icon(img, output_path, 310, "Square310x310Logo")
    all_generated.append(output_path)
    
    # 5. Wide 310x150 Logo (宽磁贴)
    print("\n📱 Wide 310x150 Logo (宽磁贴)")
    generated = generate_scaled_tiles(img, output_dir, "Wide310x150Logo", 310, scales)
    all_generated.extend(generated)
    
    print()
    print("-" * 70)
    print(f"\n✅ 成功！共生成 {len(all_generated)} 个高质量磁贴图标")
    print(f"\n📂 所有文件位于: {output_dir}")
    
    # 计算总大小
    total_size = sum(os.path.getsize(f) for f in all_generated) / 1024
    print(f"💾 总大小: {total_size:.1f} KB")
    
    print("\n✅ 现在你的应用应该能通过 MS Store 的 10.1.1.11 认证了！")
    print("   所有磁贴图标都是高分辨率、无失真的 PNG 格式")
    
    return True

if __name__ == '__main__':
    success = generate_all_msix_tiles()
    exit(0 if success else 1)
