import 'package:flutter/material.dart';

import '../../models/ai_workflow_descriptor.dart';

/// Slash Commands菜单项
class SlashCommandsMenu extends StatefulWidget {
  final List<AIWorkflowDescriptor> commands;
  final String filterText;
  final ValueChanged<AIWorkflowDescriptor> onCommandSelected;
  final bool visible;

  const SlashCommandsMenu({
    super.key,
    required this.commands,
    required this.filterText,
    required this.onCommandSelected,
    required this.visible,
  });

  @override
  State<SlashCommandsMenu> createState() => _SlashCommandsMenuState();
}

class _SlashCommandsMenuState extends State<SlashCommandsMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.1),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    if (widget.visible) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(SlashCommandsMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _selectedIndex = 0;
      _animationController.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _animationController.reverse();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredCommands = widget.commands
        .where((cmd) =>
            widget.filterText.isEmpty ||
            cmd.command
                .toLowerCase()
                .contains(widget.filterText.toLowerCase()) ||
            cmd.displayName
                .toLowerCase()
                .contains(widget.filterText.toLowerCase()))
        .toList();

    if (filteredCommands.isEmpty) {
      return const SizedBox.shrink();
    }

    // 确保selected index在范围内
    _selectedIndex = _selectedIndex.clamp(0, filteredCommands.length - 1);

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.2 : 0.08,
                ),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '可用命令',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Container(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredCommands.length,
                  itemBuilder: (context, index) {
                    final command = filteredCommands[index];
                    final isSelected = index == _selectedIndex;

                    return _SlashCommandTile(
                      command: command,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                        widget.onCommandSelected(command);
                      },
                      onHover: (hovering) {
                        if (hovering) {
                          setState(() {
                            _selectedIndex = index;
                          });
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlashCommandTile extends StatefulWidget {
  final AIWorkflowDescriptor command;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const _SlashCommandTile({
    required this.command,
    required this.isSelected,
    required this.onTap,
    required this.onHover,
  });

  @override
  State<_SlashCommandTile> createState() => _SlashCommandTileState();
}

class _SlashCommandTileState extends State<_SlashCommandTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovering = true);
        widget.onHover(true);
      },
      onExit: (_) {
        setState(() => _isHovering = false);
        widget.onHover(false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: widget.isSelected || _isHovering
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 命令icon
                if (widget.command.icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      widget.command.icon!,
                      style: const TextStyle(fontSize: 18),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '/',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                // 命令名称
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.command.command,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (widget.command.description != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.command.description!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                // 高亮指示符
                if (widget.isSelected)
                  Container(
                    width: 4,
                    height: 28,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 高级Slash Commands输入框
class SlashCommandsInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<AIWorkflowDescriptor> workflows;
  final ValueChanged<AIWorkflowDescriptor>? onCommandSelected;
  final ValueChanged<String>? onTextChanged;
  final VoidCallback? onSubmitted;
  final String? hintText;

  const SlashCommandsInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.workflows,
    this.onCommandSelected,
    this.onTextChanged,
    this.onSubmitted,
    this.hintText,
  });

  @override
  State<SlashCommandsInputField> createState() =>
      _SlashCommandsInputFieldState();
}

class _SlashCommandsInputFieldState extends State<SlashCommandsInputField> {
  bool _showSlashCommands = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text.trimLeft();
    final shouldShow = text.startsWith('/');

    if (shouldShow != _showSlashCommands) {
      setState(() {
        _showSlashCommands = shouldShow;
      });
    }

    widget.onTextChanged?.call(text);
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      setState(() {
        _showSlashCommands = false;
      });
    }
  }

  void _selectCommand(AIWorkflowDescriptor command) {
    widget.controller.clear();
    widget.onCommandSelected?.call(command);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filterText = widget.controller.text.trimLeft().substring(1).trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showSlashCommands)
          SlashCommandsMenu(
            commands: widget.workflows,
            filterText: filterText,
            onCommandSelected: _selectCommand,
            visible: _showSlashCommands,
          ),
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          decoration: InputDecoration(
            hintText: widget.hintText ?? '输入 / 查看命令',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: _showSlashCommands
                ? Icon(
                    Icons.more,
                    color: theme.colorScheme.primary,
                  )
                : null,
          ),
          onSubmitted: (_) => widget.onSubmitted?.call(),
        ),
      ],
    );
  }
}
