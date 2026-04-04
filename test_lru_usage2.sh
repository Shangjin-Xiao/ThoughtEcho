grep -rn "\b_countCache\b" lib/services/ | grep -v "clear" | grep -v "cleanExpired"
