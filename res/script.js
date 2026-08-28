document.addEventListener('DOMContentLoaded', () => {
    // ==================== 主题切换 ====================
    const themeToggle = document.getElementById('themeToggle');
    const themeIcon = document.getElementById('themeIcon');
    const body = document.body;
    const html = document.documentElement;

    const prefersReducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    // 从本地存储加载主题
    const currentTheme = localStorage.getItem('theme') || 'light';
    if (currentTheme === 'dark') {
        html.setAttribute('data-theme', 'dark');
        if (themeIcon) themeIcon.innerHTML = '&#9728;&#65039;';
    } else {
        if (themeIcon) themeIcon.innerHTML = '&#127769;';
    }

    if (themeToggle) {
        themeToggle.addEventListener('click', () => {
            const isDark = html.getAttribute('data-theme') === 'dark';
            if (isDark) {
                html.setAttribute('data-theme', 'light');
                if (themeIcon) themeIcon.innerHTML = '&#127769;';
                localStorage.setItem('theme', 'light');
            } else {
                html.setAttribute('data-theme', 'dark');
                if (themeIcon) themeIcon.innerHTML = '&#9728;&#65039;';
                localStorage.setItem('theme', 'dark');
            }
        });
    }

    // ==================== 导航高度同步 ====================
    function syncNavHeightVar() {
        const navEl = document.querySelector('nav');
        if (navEl) {
            const measuredH = navEl.offsetHeight;
            document.documentElement.style.setProperty('--mobile-nav-h', measuredH + 'px');
        }
    }
    syncNavHeightVar();
    if (document.fonts && document.fonts.ready) {
        document.fonts.ready.then(syncNavHeightVar).catch(() => {
            console.warn('Font loading detection unavailable; navigation height will sync on next resize event.');
        });
    }
    window.addEventListener('resize', syncNavHeightVar);

    // ==================== 移动端菜单 ====================
    const mobileMenuBtn = document.getElementById('mobileMenuBtn');
    const navLinks = document.getElementById('navLinks');
    const mobileMenuOverlay = document.getElementById('mobileMenuOverlay');

    if (mobileMenuBtn && navLinks) {
        mobileMenuBtn.setAttribute('aria-controls', 'navLinks');
        mobileMenuBtn.setAttribute('aria-expanded', 'false');

        function toggleMenu() {
            navLinks.classList.toggle('active');
            if (mobileMenuOverlay) mobileMenuOverlay.classList.toggle('active');
            const isOpen = navLinks.classList.contains('active');
            mobileMenuBtn.innerHTML = isOpen ? '×' : '☰';
            mobileMenuBtn.setAttribute('aria-expanded', String(isOpen));
        }

        mobileMenuBtn.addEventListener('click', toggleMenu);
        if (mobileMenuOverlay) mobileMenuOverlay.addEventListener('click', toggleMenu);

        // 点击导航链接后关闭菜单
        navLinks.querySelectorAll('a').forEach(link => {
            link.addEventListener('click', () => {
                if (navLinks.classList.contains('active')) toggleMenu();
            });
        });
    }

    // ==================== 截图数据定义 (按语言精确配置) ====================
    const screenshotData = {
        zh: [
            {
                src: 'screenshot/home_page.jpg',
                title: '主页',
                heading: '优雅的主页',
                desc: '卡片式设计清晰展示每日灵感、近期笔记和功能入口，助你快速进入创作状态。',
                width: 1080,
                height: 2234,
                alt: '主页'
            },
            {
                src: 'screenshot/note_full_editor_page.jpg',
                title: '富文本编辑器',
                heading: '强大的富文本编辑器',
                desc: '支持标题、列表、引用等多种格式，可插入图片、音频、视频，满足你多样化的记录需求。',
                width: 1080,
                height: 2210,
                alt: '富文本编辑器'
            },
            {
                src: 'screenshot/note_qa_chat_page.jpg',
                title: 'AI问答',
                heading: 'AI 智能问答',
                desc: '基于你的笔记内容，AI能够回答相关问题、提供总结、激发新灵感，成为你的私人知识助理。',
                width: 1080,
                height: 2242,
                alt: 'AI问答对话'
            },
            {
                src: 'screenshot/note_filter_sort_sheet.jpg',
                title: '筛选排序',
                heading: '智能筛选与排序',
                desc: '通过标签、内容、时间等多维度进行筛选和排序，帮你快速定位所需信息。',
                width: 1080,
                height: 2289,
                alt: '筛选与排序'
            },
            {
                src: 'screenshot/insights_page.jpg',
                title: '洞察分析',
                heading: 'AI 洞察分析',
                desc: 'AI 自动分析你的写作习惯、常用词汇和情感倾向，生成可视化图表，助你更好地了解自己。',
                width: 1080,
                height: 2245,
                alt: '洞察分析'
            },
            {
                src: 'screenshot/note_sync.jpg',
                title: '笔记同步',
                heading: '跨设备同步',
                desc: '通过局域网内的设备发现和数据同步功能，完整合并笔记，并只传输缺失或变化的媒体文件。',
                width: 1080,
                height: 2267,
                alt: '笔记同步'
            },
            {
                src: 'screenshot/theme_settings_page.jpg',
                title: '主题设置',
                heading: '个性化主题',
                desc: '内置多种色彩主题，并支持自定义设置，打造专属于你的视觉风格。',
                width: 1080,
                height: 1883,
                alt: '主题设置'
            },
            {
                src: 'screenshot/backup_restore_page.jpg',
                title: '备份恢复',
                heading: '数据备份与恢复',
                desc: '提供完整的数据备份和恢复功能，包括笔记、媒体文件和设置，保障你的数据安全。',
                width: 1080,
                height: 2047,
                alt: '备份恢复'
            }
        ],
        en: [
            {
                src: 'screenshot/l10n/en/home_page.jpg',
                title: 'Homepage',
                heading: 'Elegant Homepage',
                desc: 'Card-based design clearly displays daily inspiration, recent notes, and feature entries to help you get into a creative state quickly.',
                width: 1080,
                height: 2234,
                alt: 'Homepage'
            },
            {
                src: 'screenshot/l10n/en/note_full_editor_page.jpg',
                title: 'Rich Text Editor',
                heading: 'Powerful Rich Text Editor',
                desc: 'Supports various formats like headings, lists, quotes, and allows inserting images, audio, and video to meet your diverse recording needs.',
                width: 1080,
                height: 2210,
                alt: 'Rich Text Editor'
            },
            {
                src: 'screenshot/l10n/en/note_qa_chat_page.jpg',
                title: 'AI Q&A',
                heading: 'AI Q&A Chat',
                desc: 'Based on your notes, the AI can answer related questions, provide summaries, and spark new ideas, becoming your personal knowledge assistant.',
                width: 1080,
                height: 2242,
                alt: 'AI Q&A Chat'
            },
            {
                src: 'screenshot/l10n/en/insights_page.jpg',
                title: 'Insights',
                heading: 'AI Insights Analysis',
                desc: 'The AI automatically analyzes your writing habits, common vocabulary, and emotional tendencies, generating visual charts to help you better understand yourself.',
                width: 1080,
                height: 2245,
                alt: 'Insights Analysis'
            },
            {
                src: 'screenshot/l10n/en/theme_settings_page.jpg',
                title: 'Theme Settings',
                heading: 'Personalized Theme',
                desc: 'Built-in multiple color themes and supports custom settings to create your own unique visual style.',
                width: 1080,
                height: 1883,
                alt: 'Theme Settings'
            },
            {
                src: 'screenshot/l10n/en/webdav_sync_page.jpg',
                title: 'WebDAV Sync',
                heading: 'WebDAV Cloud Sync',
                desc: 'Support WebDAV cloud backup & sync, connect your notes with Nextcloud or Nutstore seamlessly.',
                width: 1080,
                height: 2047,
                alt: 'WebDAV Cloud Sync'
            }
        ],
        ja: [
            {
                src: 'screenshot/l10n/ja/home_page.jpg',
                title: 'ホーム',
                heading: '洗練されたホーム画面',
                desc: 'カードスタイルのデザインで、日々のひらめきや最近のノート、機能へのショートカットを一目で確認。すぐに創作に没頭できます。',
                width: 1080,
                height: 2234,
                alt: 'ホーム画面'
            }
        ],
        ko: [
            {
                src: 'screenshot/l10n/ko/home_page.jpg',
                title: '홈',
                heading: '우아하고 직관적인 홈',
                desc: '카드형 디자인으로 오늘의 영감, 최근 작성한 노트, 주요 기능을 한눈에 확인하고 창작을 시작할 수 있습니다.',
                width: 1080,
                height: 2234,
                alt: '홈 화면'
            }
        ]
    };

    // ==================== 图片模态框 (Lightbox Modal) ====================
    let currentActiveScreenshots = screenshotData.zh;
    let currentModalIndex = 0;
    const modal = document.getElementById('imageModal');
    const modalImage = document.getElementById('modalImage');
    const modalCaption = document.getElementById('modalCaption');
    const modalCloseBtn = document.getElementById('modalCloseBtn');
    const prevBtnNav = document.querySelector('.modal-prev');
    const nextBtnNav = document.querySelector('.modal-next');
    let lastActiveElement = null;

    function openModal(src, title, index) {
        if (!modal || !modalImage || !modalCaption) return;

        if (typeof index === 'number' && index >= 0 && index < currentActiveScreenshots.length) {
            currentModalIndex = index;
        } else {
            const foundIdx = currentActiveScreenshots.findIndex(s => src.includes(s.src));
            currentModalIndex = foundIdx !== -1 ? foundIdx : 0;
        }

        const currentItem = currentActiveScreenshots[currentModalIndex] || { src, title };
        const displayTitle = currentItem.title || title || '';

        lastActiveElement = document.activeElement;
        modal.classList.add('active');
        modal.setAttribute('aria-hidden', 'false');
        body.classList.add('modal-open');

        modalImage.src = currentItem.src;
        modalImage.alt = displayTitle;
        modalCaption.textContent = displayTitle;

        // 如果当前语言只有一张截图，隐藏左右翻页按钮
        const hasMultiple = currentActiveScreenshots.length > 1;
        if (prevBtnNav) prevBtnNav.style.display = hasMultiple ? '' : 'none';
        if (nextBtnNav) nextBtnNav.style.display = hasMultiple ? '' : 'none';

        if (modalCloseBtn) {
            modalCloseBtn.focus({ preventScroll: true });
        }
    }

    function changeModalImage(direction) {
        if (currentActiveScreenshots.length <= 1) return;
        currentModalIndex += direction;

        if (currentModalIndex >= currentActiveScreenshots.length) {
            currentModalIndex = 0;
        } else if (currentModalIndex < 0) {
            currentModalIndex = currentActiveScreenshots.length - 1;
        }

        const nextImage = currentActiveScreenshots[currentModalIndex];
        const displayTitle = nextImage.title || '';

        modalImage.style.opacity = '0.5';
        setTimeout(() => {
            modalImage.src = nextImage.src;
            modalImage.alt = displayTitle;
            modalCaption.textContent = displayTitle;
            modalImage.style.opacity = '1';
        }, 180);
    }

    function closeModal() {
        if (!modal) return;
        modal.classList.remove('active');
        modal.setAttribute('aria-hidden', 'true');
        body.classList.remove('modal-open');
        if (modalImage) modalImage.src = '';
        if (modalCaption) modalCaption.textContent = '';

        if (lastActiveElement && typeof lastActiveElement.focus === 'function') {
            lastActiveElement.focus({ preventScroll: true });
        }
    }

    // 模态框事件监听
    if (modal) {
        modal.addEventListener('click', closeModal);
    }
    const modalContent = document.querySelector('.modal-content');
    if (modalContent) {
        modalContent.addEventListener('click', (e) => e.stopPropagation());
    }
    if (modalCloseBtn) {
        modalCloseBtn.addEventListener('click', closeModal);
    }
    if (prevBtnNav) {
        prevBtnNav.addEventListener('click', (e) => {
            e.stopPropagation();
            changeModalImage(-1);
        });
    }
    if (nextBtnNav) {
        nextBtnNav.addEventListener('click', (e) => {
            e.stopPropagation();
            changeModalImage(1);
        });
    }

    // ESC 键与键盘左右箭头
    document.addEventListener('keydown', (e) => {
        if (!modal || !modal.classList.contains('active')) return;

        if (e.key === 'Escape') {
            closeModal();
            return;
        }
        if (e.key === 'ArrowLeft') {
            changeModalImage(-1);
            return;
        }
        if (e.key === 'ArrowRight') {
            changeModalImage(1);
            return;
        }
    });

    // 模态框内 Tab 焦点循环
    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Tab') return;
        if (!modal || !modal.classList.contains('active')) return;

        const focusables = modal.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
        const list = Array.from(focusables).filter(el => !el.hasAttribute('disabled') && el.style.display !== 'none');
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

    // ==================== 轮播图渲染与控制 ====================
    const track = document.querySelector('.carousel-track');
    const nextBtn = document.querySelector('.next-btn');
    const prevBtn = document.querySelector('.prev-btn');
    const dotsNav = document.getElementById('carouselDots');
    const carouselContainer = document.querySelector('.carousel-container');

    let currentSlideIndex = 0;
    let autoPlayInterval = null;

    function stopAutoPlay() {
        if (autoPlayInterval) {
            clearInterval(autoPlayInterval);
            autoPlayInterval = null;
        }
    }

    function startAutoPlay() {
        if (prefersReducedMotion || currentActiveScreenshots.length <= 1) return;
        stopAutoPlay();
        autoPlayInterval = setInterval(() => {
            moveToSlide(currentSlideIndex + 1);
        }, 5000);
    }

    function resetAutoPlay() {
        stopAutoPlay();
        startAutoPlay();
    }

    function moveToSlide(index) {
        if (!track || currentActiveScreenshots.length === 0) return;
        const total = currentActiveScreenshots.length;

        if (index < 0) index = total - 1;
        if (index >= total) index = 0;

        const movePercentage = (100 / total) * index;
        track.style.transform = `translateX(-${movePercentage}%)`;

        const dots = dotsNav ? Array.from(dotsNav.children) : [];
        if (dots[currentSlideIndex]) dots[currentSlideIndex].classList.remove('active');
        if (dots[index]) dots[index].classList.add('active');

        currentSlideIndex = index;
    }

    function renderScreenshots(lang) {
        currentActiveScreenshots = screenshotData[lang] || screenshotData.zh;
        currentSlideIndex = 0;
        stopAutoPlay();

        if (!track) return;
        track.innerHTML = '';
        if (dotsNav) dotsNav.innerHTML = '';

        const total = currentActiveScreenshots.length;
        track.style.width = (total * 100) + '%';
        track.style.transform = 'translateX(0%)';

        currentActiveScreenshots.forEach((item, index) => {
            const slide = document.createElement('li');
            slide.className = 'carousel-slide';
            slide.style.width = (100 / total) + '%';

            const itemDiv = document.createElement('div');
            itemDiv.className = 'screenshot-item';

            const imgDiv = document.createElement('div');
            imgDiv.className = 'screenshot-image';
            imgDiv.setAttribute('data-modal-src', item.src);
            imgDiv.setAttribute('data-modal-title', item.title);
            imgDiv.setAttribute('role', 'button');
            imgDiv.setAttribute('tabindex', '0');
            imgDiv.setAttribute('aria-label', item.title);

            const img = document.createElement('img');
            img.src = item.src;
            img.alt = item.alt || item.title;
            img.width = item.width || 1080;
            img.height = item.height || 2234;
            img.decoding = 'async';
            img.loading = index === 0 ? 'eager' : 'lazy';
            imgDiv.appendChild(img);

            const contentDiv = document.createElement('div');
            contentDiv.className = 'screenshot-content';
            const arrow = document.createElement('div');
            arrow.className = 'arrow-doodle';
            const h4 = document.createElement('h4');
            h4.textContent = item.heading || item.title;
            const p = document.createElement('p');
            p.textContent = item.desc || '';

            contentDiv.appendChild(arrow);
            contentDiv.appendChild(h4);
            contentDiv.appendChild(p);

            // 交替排版：偶数项左图右文，奇数项左文右图
            if (index % 2 === 0) {
                itemDiv.appendChild(imgDiv);
                itemDiv.appendChild(contentDiv);
            } else {
                itemDiv.appendChild(contentDiv);
                itemDiv.appendChild(imgDiv);
            }

            slide.appendChild(itemDiv);
            track.appendChild(slide);

            // 点击与键盘回车打开模态框
            imgDiv.addEventListener('click', () => {
                openModal(item.src, item.title, index);
            });
            imgDiv.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    openModal(item.src, item.title, index);
                }
            });
        });

        // 导航按钮和指示点显示状态
        if (total <= 1) {
            if (prevBtn) prevBtn.style.display = 'none';
            if (nextBtn) nextBtn.style.display = 'none';
            if (dotsNav) dotsNav.style.display = 'none';
        } else {
            if (prevBtn) prevBtn.style.display = '';
            if (nextBtn) nextBtn.style.display = '';
            if (dotsNav) {
                dotsNav.style.display = '';
                currentActiveScreenshots.forEach((_, idx) => {
                    const dot = document.createElement('button');
                    dot.type = 'button';
                    dot.className = 'carousel-dot' + (idx === 0 ? ' active' : '');
                    dot.setAttribute('aria-label', `Slide ${idx + 1}`);
                    dot.addEventListener('click', () => {
                        moveToSlide(idx);
                        resetAutoPlay();
                    });
                    dotsNav.appendChild(dot);
                });
            }
            startAutoPlay();
        }
    }

    if (nextBtn) {
        nextBtn.addEventListener('click', () => {
            moveToSlide(currentSlideIndex + 1);
            resetAutoPlay();
        });
    }

    if (prevBtn) {
        prevBtn.addEventListener('click', () => {
            moveToSlide(currentSlideIndex - 1);
            resetAutoPlay();
        });
    }

    if (carouselContainer) {
        carouselContainer.addEventListener('mouseenter', stopAutoPlay);
        carouselContainer.addEventListener('mouseleave', startAutoPlay);
    }

    // 触摸滑动支持
    if (track) {
        let touchStartX = 0;
        let touchEndX = 0;

        track.addEventListener('touchstart', e => {
            if (currentActiveScreenshots.length <= 1) return;
            touchStartX = e.changedTouches[0].screenX;
            stopAutoPlay();
        }, { passive: true });

        track.addEventListener('touchend', e => {
            if (currentActiveScreenshots.length <= 1) return;
            touchEndX = e.changedTouches[0].screenX;
            if (touchEndX < touchStartX - 50) moveToSlide(currentSlideIndex + 1);
            if (touchEndX > touchStartX + 50) moveToSlide(currentSlideIndex - 1);
            startAutoPlay();
        }, { passive: true });
    }

    // ==================== 语言切换（支持 中文/English/日本語/한국어） ====================
    const langToggle = document.getElementById('langToggle');
    const langText = document.getElementById('langText');
    const langDropdown = document.getElementById('langDropdown');
    const langOptions = document.querySelectorAll('.lang-option');

    const langDisplayNames = {
        zh: '简体中文',
        en: 'English',
        ja: '日本語',
        ko: '한국어'
    };

    function getCurrentLang() {
        if (body.classList.contains('lang-en')) return 'en';
        if (body.classList.contains('lang-ja')) return 'ja';
        if (body.classList.contains('lang-ko')) return 'ko';
        return 'zh';
    }

    function applyLanguage(lang) {
        const supported = ['zh', 'en', 'ja', 'ko'];
        const normalized = supported.includes(lang) ? lang : 'zh';

        body.classList.remove('lang-zh', 'lang-en', 'lang-ja', 'lang-ko');
        body.classList.add(`lang-${normalized}`);

        if (langText) {
            langText.textContent = langDisplayNames[normalized];
        }

        const htmlLangMap = {
            zh: 'zh-CN',
            en: 'en',
            ja: 'ja',
            ko: 'ko'
        };
        html.setAttribute('lang', htmlLangMap[normalized] || 'zh-CN');

        // 微软徽章语言同步
        const storeBadge = document.querySelector('ms-store-badge');
        if (storeBadge) {
            const badgeLangMap = {
                zh: 'zh-cn',
                en: 'en-us',
                ja: 'ja-jp',
                ko: 'ko-kr'
            };
            storeBadge.setAttribute('language', badgeLangMap[normalized] || 'zh-cn');
        }

        // 更新下拉菜单选中态
        langOptions.forEach(opt => {
            const optLang = opt.getAttribute('data-lang');
            const isMatch = optLang === normalized;
            opt.classList.toggle('active', isMatch);
            opt.setAttribute('aria-selected', String(isMatch));
        });

        localStorage.setItem('lang', normalized);
        renderScreenshots(normalized);
        syncNavHeightVar();
    }

    // 初始化语言
    const savedLang = localStorage.getItem('lang') || 'zh';
    applyLanguage(savedLang);

    // 下拉菜单事件处理
    if (langToggle && langDropdown) {
        langToggle.addEventListener('click', (e) => {
            e.stopPropagation();
            const isOpen = langDropdown.classList.contains('active');
            langDropdown.classList.toggle('active');
            langToggle.setAttribute('aria-expanded', String(!isOpen));
        });

        document.addEventListener('click', (e) => {
            if (!langToggle.contains(e.target) && !langDropdown.contains(e.target)) {
                langDropdown.classList.remove('active');
                langToggle.setAttribute('aria-expanded', 'false');
            }
        });

        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && langDropdown.classList.contains('active')) {
                langDropdown.classList.remove('active');
                langToggle.setAttribute('aria-expanded', 'false');
                langToggle.focus();
            }
        });

        langOptions.forEach(opt => {
            opt.addEventListener('click', () => {
                const targetLang = opt.getAttribute('data-lang');
                if (targetLang) {
                    applyLanguage(targetLang);
                    langDropdown.classList.remove('active');
                    langToggle.setAttribute('aria-expanded', 'false');
                }
            });
        });
    }

    // ==================== 滚动动画 ====================
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

        document.querySelectorAll('.fade-in, .slide-in-left, .slide-in-right, .scale-in').forEach(el => {
            observer.observe(el);
        });
    }

    // ==================== 平滑滚动 ====================
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            const href = this.getAttribute('href');
            if (!href || href === '#') return;

            let target = null;
            try {
                target = document.querySelector(href);
            } catch (_) {
                return;
            }

            if (target) {
                e.preventDefault();
                target.scrollIntoView({
                    behavior: prefersReducedMotion ? 'auto' : 'smooth',
                    block: 'start'
                });
            }
        });
    });

    // ==================== FAQ 手风琴逻辑 ====================
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

    // ==================== 导航栏滚动隐藏与 Scroll Spy ====================
    let lastScroll = 0;
    const nav = document.querySelector('nav');

    window.addEventListener('scroll', () => {
        const currentScroll = window.pageYOffset;
        if (nav) {
            if (currentScroll > lastScroll && currentScroll > 100) {
                nav.style.transform = 'translateY(-100%)';
            } else {
                nav.style.transform = 'translateY(0)';
            }
        }
        lastScroll = currentScroll;
    });

    const sections = document.querySelectorAll('section[id]');
    const navItems = document.querySelectorAll('.nav-links a');

    const scrollSpyOptions = {
        threshold: 0.3,
        rootMargin: "-10% 0px -50% 0px"
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

    // ==================== 回到顶部按钮 ====================
    const backToTopBtn = document.getElementById('backToTop');
    if (backToTopBtn) {
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
    }

    // ==================== 下滑提示 ====================
    const scrollIndicator = document.querySelector('.scroll-indicator');
    if (scrollIndicator) {
        scrollIndicator.setAttribute('role', 'button');
        scrollIndicator.setAttribute('tabindex', '0');
        scrollIndicator.setAttribute('aria-label', 'Scroll down');

        const scrollToFeatures = () => {
            const features = document.getElementById('features');
            if (features) features.scrollIntoView({ behavior: 'smooth' });
        };

        scrollIndicator.addEventListener('click', scrollToFeatures);
        scrollIndicator.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                scrollToFeatures();
            }
        });
    }
});