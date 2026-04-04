grep -rn "\b_filterCache\b" lib/services/ | grep -v "clear" | grep -v "cleanExpired"
