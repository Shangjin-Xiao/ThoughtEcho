        // 主题切换
        const themeToggle = document.getElementById('themeToggle');
        const themeIcon = document.getElementById('themeIcon');
        const body = document.body;
        const html = document.documentElement;

        const prefersReducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

        // 从本地存储加载主题
        const currentTheme = localStorage.getItem('theme') || 'light';
        if (currentTheme === 'dark') {
            html.setAttribute('data-theme', 'dark');
            themeIcon.innerHTML = '&#9728;&#65039;';
        } else {
            themeIcon.innerHTML = '&#127769;';
        }

        themeToggle.addEventListener('click', () => {
            const isDark = html.getAttribute('data-theme') === 'dark';
            if (isDark) {
                html.setAttribute('data-theme', 'light');
                themeIcon.innerHTML = '&#127769;';
                localStorage.setItem('theme', 'light');
            } else {
                html.setAttribute('data-theme', 'dark');
                themeIcon.innerHTML = '&#9728;&#65039;';
                localStorage.setItem('theme', 'dark');
            }
        });


        // 语言切换（修复：避免同时存在 lang-zh 与 lang-en 导致内容全隐藏）
        const langToggle = document.getElementById('langToggle');
        const langText = document.getElementById('langText');

        function getCurrentLang() {
            return body.classList.contains('lang-en') ? 'en' : 'zh';
        }

        function applyLanguage(lang) {
            const normalized = lang === 'en' ? 'en' : 'zh';
            body.classList.remove('lang-zh', 'lang-en');
            body.classList.add(`lang-${normalized}`);
            langText.textContent = normalized === 'zh' ? 'EN' : '中文';

            // 同步 html lang（利于 SEO 与读屏）
            html.setAttribute('lang', normalized === 'zh' ? 'zh-CN' : 'en');

            // 微软徽章语言（存在则同步）
            const storeBadge = document.querySelector('ms-store-badge');
            if (storeBadge) {
                storeBadge.setAttribute('language', normalized === 'zh' ? 'zh-cn' : 'en-us');
            }

            localStorage.setItem('lang', normalized);
            syncNavHeightVar();
        }

        applyLanguage(localStorage.getItem('lang') || 'zh');
        langToggle.addEventListener('click', () => {
            applyLanguage(getCurrentLang() === 'zh' ? 'en' : 'zh');
        });

        // 移动端菜单
        const mobileMenuBtn = document.getElementById('mobileMenuBtn');
        const navLinks = document.getElementById('navLinks');
        const mobileMenuOverlay = document.getElementById('mobileMenuOverlay');

        // 动态计算导航栏实际高度，防止下拉菜单与导航栏错位
        function syncNavHeightVar() {
            var measuredH = document.querySelector('nav').offsetHeight;
            document.documentElement.style.setProperty('--mobile-nav-h', measuredH + 'px');
        }
        syncNavHeightVar();
        if (document.fonts && document.fonts.ready) {
            document.fonts.ready.then(syncNavHeightVar).catch(() => {
                console.warn('Font loading detection unavailable; navigation height will sync on next resize event.');
            });
        }
        window.addEventListener('resize', syncNavHeightVar);

        mobileMenuBtn.setAttribute('aria-controls', 'navLinks');
        mobileMenuBtn.setAttribute('aria-expanded', 'false');

        function toggleMenu() {
            navLinks.classList.toggle('active');
            mobileMenuOverlay.classList.toggle('active');
            const isOpen = navLinks.classList.contains('active');
            mobileMenuBtn.innerHTML = isOpen ? '×' : '☰';
            mobileMenuBtn.setAttribute('aria-expanded', String(isOpen));
        }

        mobileMenuBtn.addEventListener('click', toggleMenu);
        mobileMenuOverlay.addEventListener('click', toggleMenu);

        // 点击导航链接后关闭菜单
        navLinks.querySelectorAll('a').forEach(link => {
            link.addEventListener('click', () => {
                if (navLinks.classList.contains('active')) toggleMenu();
            });
        });

        // 图片模态框
        let currentImageIndex = 0;
        // 定义图片列表以便轮播
        const screenshots = [
            { src: 'screenshot/home_page.jpg', titleZh: '主页', titleEn: 'Homepage' },
            { src: 'screenshot/note_full_editor_page.dart.jpg', titleZh: '富文本编辑器', titleEn: 'Rich Text Editor' },
            { src: 'screenshot/note_qa_chat_page.jpg', titleZh: 'AI问答', titleEn: 'AI Q&A' },
            { src: 'screenshot/note_filter_sort_sheet.dart.jpg', titleZh: '筛选排序', titleEn: 'Filter & Sort' },
            { src: 'screenshot/insights_page.jpg', titleZh: '洞察分析', titleEn: 'Insights' },
            { src: 'screenshot/note_sync.jpg', titleZh: '笔记同步', titleEn: 'Sync' },
            { src: 'screenshot/theme_settings_page.jpg', titleZh: '主题设置', titleEn: 'Theme Settings' },
            { src: 'screenshot/backup_restore_page.jpg', titleZh: '备份恢复', titleEn: 'Backup & Restore' }
        ];

        const modal = document.getElementById('imageModal');
        const modalImage = document.getElementById('modalImage');
        const modalCaption = document.getElementById('modalCaption');
        const modalCloseBtn = document.getElementById('modalCloseBtn');
        let lastActiveElement = null;

        function getImageTitle(img) {
            const lang = getCurrentLang();
            if (!img) return '';
            return lang === 'zh' ? img.titleZh : img.titleEn;
        }

        function openModal(src, alt) {
            // 查找当前点击图片的索引
            const index = screenshots.findIndex(s => src.includes(s.src));
            if (index !== -1) {
                currentImageIndex = index;
            }

            const img = screenshots[currentImageIndex];
            const title = getImageTitle(img) || alt || '';

            lastActiveElement = document.activeElement;
            modal.classList.add('active');
            modal.setAttribute('aria-hidden', 'false');
            body.classList.add('modal-open');

            modalImage.src = src;
            modalImage.alt = title;
            modalCaption.textContent = title;

            // 将焦点移入对话框
            if (modalCloseBtn) {
                modalCloseBtn.focus({ preventScroll: true });
            }
        }

        function changeImage(direction) {
            currentImageIndex += direction;
            
            // 循环播放逻辑
            if (currentImageIndex >= screenshots.length) {
                currentImageIndex = 0;
            } else if (currentImageIndex < 0) {
                currentImageIndex = screenshots.length - 1;
            }

            const nextImage = screenshots[currentImageIndex];
            const title = getImageTitle(nextImage);
            
            // 简单的切换效果
            modalImage.style.opacity = '0.5';
            setTimeout(() => {
                modalImage.src = nextImage.src;
                modalImage.alt = title;
                modalCaption.textContent = title;
                modalImage.style.opacity = '1';
            }, 200);
        }

        function closeModal() {
            modal.classList.remove('active');
            modal.setAttribute('aria-hidden', 'true');
            body.classList.remove('modal-open');
            modalImage.src = '';
            modalCaption.textContent = '';

            if (lastActiveElement && typeof lastActiveElement.focus === 'function') {
                lastActiveElement.focus({ preventScroll: true });
            }
        }

        // ESC 键关闭模态框
        document.addEventListener('keydown', (e) => {
            const isModalOpen = modal.classList.contains('active');
            if (!isModalOpen) return;

            if (e.key === 'Escape') {
                closeModal();
                return;
            }
            if (e.key === 'ArrowLeft') {
                changeImage(-1);
                return;
            }
            if (e.key === 'ArrowRight') {
                changeImage(1);
                return;
            }
        });

        // 模态框内 Tab 焦点循环（轻量 focus trap）
        document.addEventListener('keydown', (e) => {
            if (e.key !== 'Tab') return;
            if (!modal.classList.contains('active')) return;

            const focusables = modal.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
            const list = Array.from(focusables).filter(el => !el.hasAttribute('disabled'));
            if (list.length === 0) return;

            const first = list[0];
            const last = list[list.length - 1];
            if (e.shiftKey && document.activeElement === first) {
                e.preventDefault();
                last.focus();
            } else if (!e.shiftKey && document.activeElement === last) {
                e.preventDefault();
                first.focus();
            }
        });

        // 滚动动画
        if (prefersReducedMotion) {
            document.querySelectorAll('.fade-in, .slide-in-left, .slide-in-right, .scale-in').forEach(el => {
                el.classList.add('visible');
            });
        } else {
            const observerOptions = {
                threshold: 0.1,
                rootMargin: '0px 0px -100px 0px'
            };

            const observer = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    if (entry.isIntersecting) {
                        entry.target.classList.add('visible');
                    }
                });
            }, observerOptions);

            // 观察所有需要动画的元素
            document.querySelectorAll('.fade-in, .slide-in-left, .slide-in-right, .scale-in').forEach(el => {
                observer.observe(el);
            });
        }

        // 平滑滚动
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', function (e) {
                e.preventDefault();
                const href = this.getAttribute('href');
                if (!href || href === '#') {
                    window.scrollTo({ top: 0, behavior: prefersReducedMotion ? 'auto' : 'smooth' });
                    return;
                }

                let target = null;
                try {
                    target = document.querySelector(href);
                } catch (_) {
                    // 忽略无效选择器（例如 href="#"）
                    return;
                }

                if (target) {
                    target.scrollIntoView({
                        behavior: prefersReducedMotion ? 'auto' : 'smooth',
                        block: 'start'
                    });
                }
            });
        });

        // FAQ 手风琴逻辑
        document.querySelectorAll('.faq-question').forEach(btn => {
            btn.addEventListener('click', () => {
                const expanded = btn.getAttribute('aria-expanded') === 'true';
                const answerId = btn.getAttribute('aria-controls');
                const answer = answerId ? document.getElementById(answerId) : null;

                // 默认行为：只展开一个
                document.querySelectorAll('.faq-question[aria-expanded="true"]').forEach(openBtn => {
                    if (openBtn === btn) return;
                    openBtn.setAttribute('aria-expanded', 'false');
                    const id = openBtn.getAttribute('aria-controls');
                    const panel = id ? document.getElementById(id) : null;
                    if (panel) panel.hidden = true;
                });

                btn.setAttribute('aria-expanded', String(!expanded));
                if (answer) answer.hidden = expanded;
            });
        });

        // 导航栏滚动效果
        let lastScroll = 0;
        const nav = document.querySelector('nav');

        window.addEventListener('scroll', () => {
            const currentScroll = window.pageYOffset;
            
            if (currentScroll > lastScroll && currentScroll > 100) {
                nav.style.transform = 'translateY(-100%)';
            } else {
                nav.style.transform = 'translateY(0)';
            }
            
            lastScroll = currentScroll;
        });

        // 滚动监听 (Scroll Spy)
        const sections = document.querySelectorAll('section[id]');
        const navItems = document.querySelectorAll('.nav-links a');

        const scrollSpyOptions = {
            threshold: 0.3, // 30% 可见时触发
            rootMargin: "-10% 0px -50% 0px" // 调整触发线，使其更符合视觉中心
        };

        const scrollSpy = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    const id = entry.target.getAttribute('id');
                    navItems.forEach(link => {
                        link.classList.toggle('active', link.getAttribute('href') === `#${id}`);
                    });
                }
            });
        }, scrollSpyOptions);

        sections.forEach(section => {
            scrollSpy.observe(section);
        });

        // 回到顶部按钮逻辑
        const backToTopBtn = document.getElementById('backToTop');
        
        window.addEventListener('scroll', () => {
            if (window.pageYOffset > 500) {
                backToTopBtn.classList.add('visible');
            } else {
                backToTopBtn.classList.remove('visible');
            }
        });

        backToTopBtn.addEventListener('click', () => {
            window.scrollTo({ top: 0, behavior: 'smooth' });
        });

        // ==================== 轮播图逻辑 ====================
        const track = document.querySelector('.carousel-track');
        const nextBtn = document.querySelector('.next-btn');
        const prevBtn = document.querySelector('.prev-btn');
        const dotsNav = document.getElementById('carouselDots');

        if (track && nextBtn && prevBtn && dotsNav) {
            const slides = Array.from(track.children);
            let currentSlideIndex = 0;
            let autoPlayInterval;

            // 初始化轮播尺寸
            track.style.width = (slides.length * 100) + '%';
            slides.forEach(slide => {
                slide.style.width = (100 / slides.length) + '%';
            });

            // 生成圆点
            slides.forEach((_, index) => {
                const dot = document.createElement('button');
                dot.type = 'button';
                dot.classList.add('carousel-dot');
                if (index === 0) dot.classList.add('active');
                dot.addEventListener('click', () => moveToSlide(index));
                dotsNav.appendChild(dot);
            });

            const dots = Array.from(dotsNav.children);

            function moveToSlide(index) {
                if (slides.length === 0) return;

                // 循环逻辑
                if (index < 0) index = slides.length - 1;
                if (index >= slides.length) index = 0;

                // 修正：移动距离应为 (100 / slides.length) * index
                const movePercentage = (100 / slides.length) * index;
                track.style.transform = 'translateX(-' + movePercentage + '%)';

                // 更新圆点状态
                if (dots[currentSlideIndex]) dots[currentSlideIndex].classList.remove('active');
                if (dots[index]) dots[index].classList.add('active');

                currentSlideIndex = index;
            }

            // 按钮事件
            nextBtn.addEventListener('click', () => {
                moveToSlide(currentSlideIndex + 1);
                resetAutoPlay();
            });

            prevBtn.addEventListener('click', () => {
                moveToSlide(currentSlideIndex - 1);
                resetAutoPlay();
            });

            // 自动播放
            function startAutoPlay() {
                if (prefersReducedMotion) return;
                autoPlayInterval = setInterval(() => {
                    moveToSlide(currentSlideIndex + 1);
                }, 5000);
            }

            function stopAutoPlay() {
                clearInterval(autoPlayInterval);
            }

            function resetAutoPlay() {
                stopAutoPlay();
                startAutoPlay();
            }

            // 鼠标悬停暂停
            const carouselContainer = document.querySelector('.carousel-container');
            if (carouselContainer) {
                carouselContainer.addEventListener('mouseenter', stopAutoPlay);
                carouselContainer.addEventListener('mouseleave', startAutoPlay);
            }

            // 触摸滑动支持 (Mobile Swipe)
            let touchStartX = 0;
            let touchEndX = 0;

            track.addEventListener('touchstart', e => {
                touchStartX = e.changedTouches[0].screenX;
                stopAutoPlay();
            }, { passive: true });

            track.addEventListener('touchend', e => {
                touchEndX = e.changedTouches[0].screenX;
                if (touchEndX < touchStartX - 50) moveToSlide(currentSlideIndex + 1);
                if (touchEndX > touchStartX + 50) moveToSlide(currentSlideIndex - 1);
                startAutoPlay();
            }, { passive: true });

            startAutoPlay();
        }

        // 截图/滚动提示：键盘可触达
        document.querySelectorAll('.screenshot-image').forEach(el => {
            el.setAttribute('role', 'button');
            el.setAttribute('tabindex', '0');
            el.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    el.click();
                }
            });
        });

        const scrollIndicator = document.querySelector('.scroll-indicator');
        if (scrollIndicator) {
            scrollIndicator.setAttribute('role', 'button');
            scrollIndicator.setAttribute('tabindex', '0');
            scrollIndicator.setAttribute('aria-label', 'Scroll down');
            scrollIndicator.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    scrollIndicator.click();
                }
            });
        }


// ==================== Event Listeners for Removed Inline Handlers ====================

// Scroll Indicator
const scrollIndicator = document.querySelector('.scroll-indicator');
if (scrollIndicator) {
    scrollIndicator.addEventListener('click', () => {
        const features = document.getElementById('features');
        if (features) features.scrollIntoView({ behavior: 'smooth' });
    });
}

// Screenshot Images (Modal Open)
document.querySelectorAll('.screenshot-image').forEach(el => {
    el.addEventListener('click', () => {
        const src = el.getAttribute('data-modal-src');
        const title = el.getAttribute('data-modal-title');
        // Fallback to img alt if title is missing
        const img = el.querySelector('img');
        const alt = img ? img.alt : '';
        if (src) {
            openModal(src, title || alt);
        }
    });
});

// Modal Close
const modalEl = document.getElementById('imageModal');
if (modalEl) {
    modalEl.addEventListener('click', closeModal);
}

// Modal Content Stop Propagation
const modalContent = document.querySelector('.modal-content');
if (modalContent) {
    modalContent.addEventListener('click', (e) => e.stopPropagation());
}

// Modal Close Button
if (modalCloseBtn) {
    modalCloseBtn.addEventListener('click', closeModal);
}

// Modal Nav Buttons
const prevBtnNav = document.querySelector('.modal-prev');
const nextBtnNav = document.querySelector('.modal-next');

if (prevBtnNav) {
    prevBtnNav.addEventListener('click', (e) => {
        e.stopPropagation(); // Prevent modal close
        changeImage(-1);
    });
}

if (nextBtnNav) {
    nextBtnNav.addEventListener('click', (e) => {
        e.stopPropagation(); // Prevent modal close
        changeImage(1);
    });
}

// Mobile Menu Logic
const mobileMenuBtn = document.getElementById('mobileMenuBtn');
const mobileMenuOverlay = document.getElementById('mobileMenuOverlay');
const navLinks = document.getElementById('navLinks');

if (mobileMenuBtn) {
    mobileMenuBtn.addEventListener('click', () => {
        const isActive = navLinks.classList.contains('active');
        if (isActive) {
            navLinks.classList.remove('active');
            if (mobileMenuOverlay) mobileMenuOverlay.classList.remove('active');
            mobileMenuBtn.setAttribute('aria-expanded', 'false');
            document.body.classList.remove('menu-open');
        } else {
            navLinks.classList.add('active');
            if (mobileMenuOverlay) mobileMenuOverlay.classList.add('active');
            mobileMenuBtn.setAttribute('aria-expanded', 'true');
            document.body.classList.add('menu-open');
        }
    });

    // Close menu when clicking overlay
    if (mobileMenuOverlay) {
        mobileMenuOverlay.addEventListener('click', () => {
            navLinks.classList.remove('active');
            mobileMenuOverlay.classList.remove('active');
            mobileMenuBtn.setAttribute('aria-expanded', 'false');
            document.body.classList.remove('menu-open');
        });
    }

    // Close menu when clicking a link
    if (navLinks) {
        const links = navLinks.querySelectorAll('a');
        links.forEach(link => {
            link.addEventListener('click', () => {
                navLinks.classList.remove('active');
                if (mobileMenuOverlay) mobileMenuOverlay.classList.remove('active');
                mobileMenuBtn.setAttribute('aria-expanded', 'false');
                document.body.classList.remove('menu-open');
            });
        });
    }
}
