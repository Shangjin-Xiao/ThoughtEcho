#!/usr/bin/env python3
"""
生成高质量的 Windows 应用程序图标（.ico）
包含多种分辨率以避免在任务栏、安装包等位置失真
使用 ImageMagick 确保最佳兼容性和质量
"""

import os
import sys
import subprocess

def generate_high_quality_ico(source_path, output_path):
    """
    从源图片生成包含多种尺寸的高质量 ICO 文件
    
    ICO 文件应包含以下尺寸以确保在所有场景下清晰显示：
    - 16x16: 小图标、文件资源管理器
    - 24x24: 列表视图
    - 32x32: 任务栏（标准 DPI）
    - 48x48: Windows 7/8 开始菜单
    - 64x64: 高 DPI 任务栏
    - 96x96: 超高 DPI
    - 128x128: 大图标视图
    - 256x256: 超大图标视图、Windows 10/11 高 DPI
    """
    
    print(f"正在从 {source_path} 生成高质量 ICO 文件...")
    
    try:
        # 检查 ImageMagick 是否安装
        result = subprocess.run(['convert', '--version'], 
                              capture_output=True, text=True, check=False)
        if result.returncode != 0:
            print("❌ 错误：未安装 ImageMagick")
            print("   请运行: sudo apt-get install imagemagick")
            return False
        
        # 使用 ImageMagick 生成包含多种尺寸的 ICO
        # -define icon:auto-resize 会自动生成指定尺寸的图标
        cmd = [
            'convert',
            source_path,
            '-background', 'transparent',
            '-define', 'icon:auto-resize=256,128,96,64,48,32,24,16',
            output_path
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        
        # 验证生成的 ICO 文件
        identify_result = subprocess.run(
            ['identify', output_path],
            capture_output=True, text=True, check=True
        )
        
        # 统计包含的图标数量
        icon_count = len(identify_result.stdout.strip().split('\n'))
        
        print(f"\n✅ 成功生成高质量 ICO 文件: {output_path}")
        print(f"   包含 {icon_count} 种尺寸")
        
        # 显示所有尺寸
        for line in identify_result.stdout.strip().split('\n'):
            if 'ICO' in line or 'PNG' in line:
                # 提取尺寸信息
                parts = line.split()
                for i, part in enumerate(parts):
                    if 'x' in part and part.replace('x', '').replace('+', '').replace('0', '').isdigit():
                        size = part.split('+')[0] if '+' in part else part
                        print(f"   ✓ {size}")
                        break
        
        # 验证文件大小
        file_size = os.path.getsize(output_path)
        print(f"\n   文件大小: {file_size / 1024:.1f} KB")
        
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"❌ 运行 ImageMagick 时出错: {e}")
        if e.stderr:
            print(f"   错误信息: {e.stderr}")
        return False
    except Exception as e:
        print(f"❌ 生成 ICO 文件时出错: {e}")
        return False

def main():
    # 项目根目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    
    # 源图标路径（使用项目中的高分辨率源图）
    source_candidates = [
        os.path.join(project_root, 'icon.png'),
        os.path.join(project_root, 'res', 'icon.png'),
        os.path.join(project_root, 'assets', 'icon.png'),
    ]
    
    source_path = None
    for candidate in source_candidates:
        if os.path.exists(candidate):
            source_path = candidate
            break
    
    if not source_path:
        print("❌ 错误：找不到源图标文件")
        print("   请确保以下任一路径存在高分辨率 PNG 图标：")
        for path in source_candidates:
            print(f"   - {path}")
        sys.exit(1)
    
    # 输出路径
    output_path = os.path.join(project_root, 'windows', 'runner', 'resources', 'app_icon.ico')
    
    # 确保输出目录存在
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    # 生成 ICO 文件
    success = generate_high_quality_ico(source_path, output_path)
    
    if success:
        print("\n📋 后续步骤：")
        print("   1. 重新构建 Windows 应用")
        print("   2. 检查任务栏和开始菜单中的图标是否清晰")
        print("   3. 如果需要，可以重新生成 MSIX 包")
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
