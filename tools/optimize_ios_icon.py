from PIL import Image, ImageChops
import os

def create_large_ios_icon(input_path, output_path, padding_percent=0.1):
    try:
        img = Image.open(input_path).convert("RGBA")
        
        # 1. Determine background color from top-left corner
        bg_color = img.getpixel((0, 0))
        print(f"Detected background color: {bg_color}")
        
        # 2. Create a mask of pixels that match the background color
        # We'll use a difference method to find non-background pixels
        bg_image = Image.new("RGBA", img.size, bg_color)
        diff = ImageChops.difference(img, bg_image)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        
        if bbox:
            print(f"Content bounding box: {bbox}")
            # 3. Crop to the content (the book)
            content = img.crop(bbox)
            
            # 4. Create a new 1024x1024 canvas with the background color
            target_size = (1024, 1024)
            new_icon = Image.new("RGBA", target_size, bg_color)
            
            # 5. Resize content to fit target size minus padding
            # User wants it "large", so let's minimize padding. 
            # iOS safe zone is usually around 1/6th, but user wants "full".
            # Let's try 5% padding on each side (10% total) or even less if requested.
            # User said "crop blue part... make it normal size... or full".
            # Let's go with very small padding to maximize size, e.g., 5% total margin.
            
            content_width, content_height = content.size
            aspect_ratio = content_width / content_height
            
            # Calculate max dimensions for content
            max_w = int(target_size[0] * (1 - padding_percent))
            max_h = int(target_size[1] * (1 - padding_percent))
            
            if max_w / max_h > aspect_ratio:
                new_w = int(max_h * aspect_ratio)
                new_h = max_h
            else:
                new_w = max_w
                new_h = int(max_w / aspect_ratio)
                
            content_resized = content.resize((new_w, new_h), Image.Resampling.LANCZOS)
            
            # 6. Paste centered
            x = (target_size[0] - new_w) // 2
            y = (target_size[1] - new_h) // 2
            
            # Use the content as a mask for itself if it has transparency, 
            # but here we cropped from an image that might have the background color baked in 
            # if the tolerance wasn't perfect. 
            # However, since we cropped based on diff, 'content' is just the rectangular crop.
            # It still has the original pixels.
            new_icon.paste(content_resized, (x, y), content_resized)
            
            new_icon.save(output_path)
            print(f"Saved optimized iOS icon to {output_path}")
            return True
        else:
            print("Could not detect content (image might be solid color).")
            return False
            
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    # Use the original icon as source to ensure best quality
    create_large_ios_icon("icon.png", "icon_ios_large.png", padding_percent=0.15) 
    # 0.15 padding (15%) leaves some breathing room but makes it much larger than a small center logo.
    # Adjust padding_percent to 0.0 for "full bleed" if the icon shape allows.
    # Given it's a book, 10-15% is usually good for iOS "Safe Zone".
