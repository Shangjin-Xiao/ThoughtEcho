import 'package:flutter/material.dart';

class SlidingCard extends StatefulWidget {
  final List<Widget> pages;

  const SlidingCard({
    Key? key,
    required this.pages,
  }) : super(key: key);

  @override
  State<SlidingCard> createState() => _SlidingCardState();
}

class _SlidingCardState extends State<SlidingCard> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            children: widget.pages,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.pages.length,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPage == index
                    ? Theme.of(context).primaryColor
                    : Colors.grey,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}