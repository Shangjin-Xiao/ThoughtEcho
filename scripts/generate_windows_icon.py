#!/usr/bin/env python3
"""
生成高质量的 Windows ICO 文件
包含多种尺寸以确保在任务栏、开始菜单、安装包等位置清晰显示
"""

from PIL import Image
import os

def generate_windows_icon():
    """从源图标生成包含多种尺寸的高质量 ICO 文件"""
    
    # 查找源图标
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    
    # 可能的源图标位置
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
        print("  请确保以下位置之一存在图标:")
        for path in source_paths:
            print(f"    - {path}")
        return False
    
    # 输出路径
    output_path = os.path.join(project_root, 'windows', 'runner', 'resources', 'app_icon.ico')
    
    try:
        # 打开源图像
        img = Image.open(source_icon)
        
        # 转换为 RGBA 模式（如果不是的话）
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        
        print(f"✓ 源图像尺寸: {img.size}")
        
        # Windows ICO 应该包含的所有尺寸
        # 这些尺寸覆盖了所有 Windows 显示场景：
        # 16x16 - 小图标（资源管理器列表视图）
        # 32x32 - 中等图标（资源管理器、任务栏）
        # 48x48 - 大图标（桌面图标）
        # 64x64 - 额外大图标（某些高 DPI 场景）
        # 128x128 - 超大图标（Windows 7+ 缩略图）
        # 256x256 - 最大尺寸（高 DPI 显示、Windows 10+ 开始菜单）
        sizes = [
            (16, 16),
            (32, 32),
            (48, 48),
            (64, 64),
            (128, 128),
            (256, 256),
        ]
        
        # 生成所有尺寸的图像
        icons = []
        for size in sizes:
            # 使用高质量的 Lanczos 重采样算法
            resized = img.resize(size, Image.Resampling.LANCZOS)
            icons.append(resized)
            print(f"✓ 生成 {size[0]}x{size[1]} 图标")
        
        # 保存为 ICO 文件，包含所有尺寸
        # 注意：PIL 的 ICO 保存需要传递所有图像
        img.save(
            output_path,
            format='ICO',
            sizes=sizes
        )
        
        print(f"\n✓ 成功生成高质量 ICO 文件: {output_path}")
        print(f"  包含 {len(sizes)} 种尺寸")
        
        # 验证生成的文件
        file_size = os.path.getsize(output_path)
        print(f"  文件大小: {file_size / 1024:.1f} KB")
        
        return True
        
    except Exception as e:
        print(f"\n✗ 生成 ICO 文件时出错: {e}")
        return False

if __name__ == '__main__':
    print("=" * 60)
    print("Windows 高质量 ICO 图标生成器")
    print("=" * 60)
    print()
    
    success = generate_windows_icon()
    
    print()
    if success:
        print("✓ 完成！新的高质量图标已就绪")
        print("  现在在任务栏、开始菜单和安装包中都会清晰显示")
    else:
        print("✗ 生成失败")
    print()
