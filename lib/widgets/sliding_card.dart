import 'package:flutter/material.dart';

class SlidingCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onSlideComplete;

  const SlidingCard({
    Key? key,
    required this.child,
    required this.onSlideComplete,
  }) : super(key: key);

  @override
  State<SlidingCard> createState() => _SlidingCardState();
}

class _SlidingCardState extends State<SlidingCard> {
  final PageController _pageController = PageController();
  bool _hasCompletedSlide = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return PageView(
      controller: _pageController,
      onPageChanged: (index) {
        if (index == 1 && !_hasCompletedSlide) {
          _hasCompletedSlide = true;
          widget.onSlideComplete();
        }
      },
      children: [
        // 第一页：显示每日一言
        Container(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.format_quote, size: 40),
                  const SizedBox(height: 16),
                  widget.child,
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.arrow_forward,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 127),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '向左滑动记录感想',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 127),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // 第二页：空白页，用于触发回调
        Container(),
      ],
    );
  }
} 