import 'dart:math';

import 'package:flutter/material.dart' hide TableRow;

import '../table_data.dart';
import '../trees.dart';
import '../ui/theme.dart';
import 'collapsible_mixin.dart';
import 'theme.dart';

/// A table that displays in a collection of [data], based on a collection
/// of [ColumnData].
///
/// The [ColumnData] gives this table information about how to size its
/// columns, and how to present each row of `data`
class FlatTable<T> extends StatefulWidget {
  const FlatTable({
    Key key,
    @required this.columns,
    @required this.data,
    @required this.keyFactory,
    @required this.onItemSelected,
  })  : assert(columns != null),
        assert(keyFactory != null),
        assert(data != null),
        assert(onItemSelected != null),
        super(key: key);

  final List<ColumnData<T>> columns;

  final List<T> data;

  /// Factory that creates keys for each row in this table.
  final Key Function(T data) keyFactory;

  final ItemCallback<T> onItemSelected;

  @override
  _FlatTableState<T> createState() => _FlatTableState<T>();
}

class _FlatTableState<T> extends State<FlatTable<T>> {
  List<double> columnWidths;

  @override
  void initState() {
    super.initState();
    columnWidths = _computeColumnWidths();
  }

  @override
  void didUpdateWidget(FlatTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    columnWidths = _computeColumnWidths();
  }

  List<double> _computeColumnWidths() {
    final widths = <double>[];
    for (ColumnData<T> column in widget.columns) {
      double width;
      if (column.fixedWidthPx != null) {
        width = column.fixedWidthPx;
      } else {
        width = _Table.defaultColumnWidth;
      }
      widths.add(width);
    }
    return widths;
  }

  @override
  Widget build(BuildContext context) {
    return _Table<T>(
      itemCount: widget.data.length,
      columns: widget.columns,
      columnWidths: columnWidths,
      startAtBottom: true,
      tableRowBuilder: _buildRow,
    );
  }

  Widget _buildRow(BuildContext context, int index) {
    final node = widget.data[index];
    return TableRow<T>(
      key: widget.keyFactory(node),
      node: node,
      onPressed: widget.onItemSelected,
      columns: widget.columns,
      columnWidths: columnWidths,
      backgroundColor: TableRow.colorFor(context, index),
    );
  }
}

// TODO(https://github.com/flutter/devtools/issues/1657)

/// A table that shows [TreeNode]s.
///
/// This takes in a collection of [dataRoots], and a collection of [ColumnData].
/// It takes at most one [TreeColumnData].
///
/// The [ColumnData] gives this table information about how to size its
/// columns, how to present each row of `data`, and which rows to show.
///
/// To lay the contents out, this table's [_TreeTableState] creates a flattened
/// list of the tree hierarchy. It then uses the nesting level of the
/// deepest row in [dataRoots] to determine how wide to make the [treeColumn].
///
/// If [dataRoots.length] > 1, there are multiple trees in this tree table. In
/// this case, tree table operations (expand all, collapse all, sort, etc.) will
/// be applied to every tree.
class TreeTable<T extends TreeNode<T>> extends StatefulWidget {
  TreeTable({
    Key key,
    @required this.columns,
    @required this.treeColumn,
    @required this.dataRoots,
    @required this.keyFactory,
  })  : assert(columns.contains(treeColumn)),
        assert(columns != null),
        assert(keyFactory != null),
        assert(dataRoots != null),
        super(key: key);

  /// The columns to show in this table.
  final List<ColumnData<T>> columns;

  /// The column of the table to treat as expandable.
  final TreeColumnData<T> treeColumn;

  /// The tree structures of rows to show in this table.
  final List<T> dataRoots;

  /// Factory that creates keys for each row in this table.
  final Key Function(T) keyFactory;

  @override
  _TreeTableState<T> createState() => _TreeTableState<T>();
}

class _TreeTableState<T extends TreeNode<T>> extends State<TreeTable<T>>
    with TickerProviderStateMixin {
  List<T> items;
  List<T> animatingChildren = [];
  Set<T> animatingChildrenSet = {};
  T animatingNode;
  List<double> columnWidths;
  List<bool> rootsExpanded;

  /// The number of items to show when animating out the tree table.
  static const itemsToShowWhenAnimating = 50;

  @override
  void initState() {
    super.initState();
    rootsExpanded = List.generate(
        widget.dataRoots.length, (index) => widget.dataRoots[index].isExpanded);
    _updateItems();
  }

  @override
  void didUpdateWidget(TreeTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    rootsExpanded = List.generate(
        widget.dataRoots.length, (index) => widget.dataRoots[index].isExpanded);
    _updateItems();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _updateItems() {
    setState(() {
      items = _buildFlatList(widget.dataRoots);
      // Leave enough space for the animating children during the animation.
      columnWidths = _computeColumnWidths([...items, ...animatingChildren]);
    });
  }

  void _onItemsAnimated() {
    setState(() {
      animatingChildren = [];
      animatingChildrenSet = {};
      // Remove the animating children from the column width computations.
      columnWidths = _computeColumnWidths(items);
    });
  }

  void _onItemPressed(T node) {
    /// Rebuilds the table whenever the tree structure has been updated
    if (!node.isExpandable) return;
    setState(() {
      animatingNode = node;
      List<T> nodeChildren;
      if (node.isExpanded) {
        // Compute the children of the expanded node before collapsing.
        nodeChildren = _buildFlatList([node]);
        node.collapse();
      } else {
        node.expand();
        // Compute the children of the collapsed node after expanding it.
        nodeChildren = _buildFlatList([node]);
      }
      // The first item will be node itself. We will take the next few items
      // to generate a convincing expansion animation without creating
      // potentially thousands of widgets.
      animatingChildren =
          nodeChildren.skip(1).take(itemsToShowWhenAnimating).toList();
      animatingChildrenSet = Set.of(animatingChildren);

      // Update the tracked expansion of the root node if needed.
      if (widget.dataRoots.contains(node)) {
        final rootIndex = widget.dataRoots.indexOf(node);
        rootsExpanded[rootIndex] = node.isExpanded;
      }
    });
    _updateItems();
  }

  List<double> _computeColumnWidths(List<T> flattenedList) {
    final firstRoot = widget.dataRoots.first;
    TreeNode deepest = firstRoot;
    // This will use the width of all rows in the table, even the rows
    // that are hidden by nesting.
    // We may want to change this to using a flattened list of only
    // the list items that should show right now.
    for (var node in flattenedList) {
      if (node.level > deepest.level) {
        deepest = node;
      }
    }
    final widths = <double>[];
    for (ColumnData<T> column in widget.columns) {
      double width = column.getNodeIndentPx(deepest);
      if (column.fixedWidthPx != null) {
        width += column.fixedWidthPx;
      } else {
        // TODO(djshuckerow): measure the text of the longest content
        // to get an idea for how wide this column should be.
        // Text measurement is a somewhat expensive algorithm, so we don't
        // want to do it for every row in the table, only the row
        // we are confident is the widest.  A reasonable heuristic is the row
        // with the longest text, but because of variable-width fonts, this is
        // not always true.
        width += _Table.defaultColumnWidth;
      }
      widths.add(width);
    }
    return widths;
  }

  void traverse(T node, bool Function(T) callback) {
    if (node == null) return;
    final shouldContinue = callback(node);
    if (shouldContinue) {
      for (var child in node.children) {
        traverse(child, callback);
      }
    }
  }

  List<T> _buildFlatList(List<T> roots) {
    final flatList = <T>[];
    for (T root in roots) {
      traverse(root, (n) {
        flatList.add(n);
        return n.isExpanded;
      });
    }
    return flatList;
  }

  @override
  Widget build(BuildContext context) {
    return _Table<T>(
      columns: widget.columns,
      itemCount: items.length,
      columnWidths: columnWidths,
      tableRowBuilder: _buildRow,
    );
  }

  Widget _buildRow(BuildContext context, int index) {
    Widget rowForNode(T node) {
      return TableRow<T>(
        key: widget.keyFactory(node),
        node: node,
        onPressed: _onItemPressed,
        backgroundColor: TableRow.colorFor(context, index),
        columns: widget.columns,
        columnWidths: columnWidths,
        expandableColumn: widget.treeColumn,
        isExpanded: node.isExpanded,
        isExpandable: node.isExpandable,
        isShown: node.shouldShow(),
        expansionChildren:
            node != animatingNode || animatingChildrenSet.contains(node)
                ? null
                : [for (var child in animatingChildren) rowForNode(child)],
        onExpansionCompleted: _onItemsAnimated,
        // TODO(https://github.com/flutter/devtools/issues/1361): alternate table
        // row colors, even when the table has collapsed rows.
      );
    }

    final node = items[index];
    if (animatingChildrenSet.contains(node)) return const SizedBox();
    return rowForNode(node);
  }
}

class _Table<T> extends StatelessWidget {
  const _Table(
      {Key key,
      @required this.itemCount,
      @required this.columns,
      @required this.columnWidths,
      @required this.tableRowBuilder,
      this.startAtBottom = false})
      : super(key: key);

  final int itemCount;
  final bool startAtBottom;
  final List<ColumnData<T>> columns;
  final List<double> columnWidths;
  final IndexedWidgetBuilder tableRowBuilder;

  /// The width to assume for columns that don't specify a width.
  static const defaultColumnWidth = 500.0;

  /// The maximum height to allow for rows in the table.
  ///
  /// When rows in the table expand or collapse, they will animate between
  /// a height of 0 and a height of [defaultRowHeight].
  static const defaultRowHeight = 42.0;

  /// How much padding to place around the beginning
  /// and end of each row in the table.
  static const rowHorizontalPadding = 16.0;

  /// The width of all columns in the table, with additional padding.
  double get tableWidth =>
      columnWidths.reduce((x, y) => x + y) + (2 * rowHorizontalPadding);

  Widget _buildItem(BuildContext context, int index) {
    if (startAtBottom) {
      index = itemCount - index - 1;
    }

    return tableRowBuilder(context, index);
  }

  @override
  Widget build(BuildContext context) {
    final itemDelegate = SliverChildBuilderDelegate(
      _buildItem,
      childCount: itemCount,
    );

    return LayoutBuilder(builder: (context, constraints) {
      return Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: max(
              constraints.widthConstraints().maxWidth,
              tableWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TableRow.tableHeader(
                  key: const Key('Table header'),
                  columns: columns,
                  columnWidths: columnWidths,
                  onPressed: (_) {},
                ),
                Expanded(
                  child: Scrollbar(
                    child: ListView.custom(
                      reverse: startAtBottom,
                      childrenDelegate: itemDelegate,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Callback for when a specific item in a table is selected.
typedef ItemCallback<T> = void Function(T item);

/// Presents a [node] as a row in a table.
///
/// When the given [node] is null, this widget will instead present
/// column headings.
@visibleForTesting
class TableRow<T> extends StatefulWidget {
  /// Constructs a [TableRow] that presents the column values for
  /// [node].
  const TableRow({
    Key key,
    @required this.node,
    @required this.columns,
    @required this.onPressed,
    @required this.columnWidths,
    this.backgroundColor,
    this.expandableColumn,
    this.expansionChildren,
    this.onExpansionCompleted,
    this.isExpanded = false,
    this.isExpandable = false,
    this.isShown = true,
  }) : super(key: key);

  /// Constructs a [TableRow] that presents the column titles instead
  /// of any [node].
  const TableRow.tableHeader({
    Key key,
    @required this.columns,
    @required this.columnWidths,
    @required this.onPressed,
  })  : node = null,
        isExpanded = false,
        isExpandable = false,
        expandableColumn = null,
        isShown = true,
        backgroundColor = null,
        expansionChildren = null,
        onExpansionCompleted = null,
        super(key: key);

  final T node;
  final List<ColumnData<T>> columns;
  final ItemCallback<T> onPressed;
  final List<double> columnWidths;

  /// Which column, if any, should show expansion affordances
  /// and nested rows.
  final ColumnData<T> expandableColumn;

  /// Whether or not this row is expanded.
  ///
  /// This dictates the orientation of the expansion arrow
  /// that is drawn in the [expandableColumn].
  ///
  /// Only meaningful if [isExpanded] is true.
  final bool isExpanded;

  /// Whether or not this row can be expanded.
  ///
  /// This dictates whether an expansion arrow is
  /// drawn in the [expandableColumn].
  final bool isExpandable;

  /// Whether or not this row is shown.
  ///
  /// When the value is toggled, this row will animate in or out.
  final bool isShown;

  /// The children to show when the expand animation of this widget is running.
  final List<Widget> expansionChildren;
  final VoidCallback onExpansionCompleted;

  /// The background color of the row.
  ///
  /// If null, defaults to `Theme.of(context).canvasColor`.
  final Color backgroundColor;

  /// Gets a color to use for this row at a given index.
  static Color colorFor(BuildContext context, int index) {
    final theme = Theme.of(context);
    final alternateColor = ThemedColor(devtoolsGrey[50], devtoolsGrey[900]);
    return index % 2 == 0 ? alternateColor : theme.canvasColor;
  }

  @override
  _TableRowState<T> createState() => _TableRowState<T>();
}

class _TableRowState<T> extends State<TableRow<T>>
    with TickerProviderStateMixin, CollapsibleAnimationMixin {
  Key contentKey;

  @override
  void initState() {
    super.initState();
    contentKey = ValueKey(this);
    expandController.addStatusListener((status) {
      setState(() {});
      if ([AnimationStatus.completed, AnimationStatus.dismissed]
              .contains(status) &&
          widget.onExpansionCompleted != null) {
        widget.onExpansionCompleted();
      }
    });
  }

  @override
  void didUpdateWidget(TableRow<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    setExpanded(widget.isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final row = tableRowFor(context);

    final box = SizedBox(
      height: _Table.defaultRowHeight,
      child: Material(
        color: widget.backgroundColor ?? Theme.of(context).canvasColor,
        child: InkWell(
          key: contentKey,
          onTap: () => widget.onPressed(widget.node),
          child: row,
        ),
      ),
    );
    if (widget.expansionChildren == null) return box;

    return AnimatedBuilder(
      animation: expandCurve,
      builder: (context, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            box,
            for (var c in widget.expansionChildren)
              SizedBox(
                height: _Table.defaultRowHeight * expandCurve.value,
                child: OverflowBox(
                  minHeight: 0.0,
                  maxHeight: _Table.defaultRowHeight,
                  alignment: Alignment.topCenter,
                  child: c,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Presents the content of this row.
  Widget tableRowFor(BuildContext context) {
    Alignment alignmentFor(ColumnData<T> column) {
      switch (column.alignment) {
        case ColumnAlignment.center:
          return Alignment.center;
        case ColumnAlignment.right:
          return Alignment.centerRight;
        case ColumnAlignment.left:
        default:
          return Alignment.centerLeft;
      }
    }

    Widget columnFor(ColumnData<T> column, double columnWidth) {
      Widget content;
      final node = widget.node;
      if (node == null) {
        content = Text(
          column.title,
          overflow: TextOverflow.ellipsis,
        );
      } else {
        final padding = column.getNodeIndentPx(node);
        content = Text(
          '${column.getDisplayValue(node)}',
          overflow: TextOverflow.ellipsis,
        );
        if (column == widget.expandableColumn) {
          final expandIndicator = widget.isExpandable
              ? RotationTransition(
                  turns: expandArrowAnimation,
                  child: const Icon(
                    Icons.expand_more,
                    size: 16.0,
                  ),
                )
              : const SizedBox(width: 16.0, height: 16.0);
          content = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              expandIndicator,
              Expanded(child: content),
            ],
          );
        }
        content = Padding(
          padding: EdgeInsets.only(left: padding),
          child: ClipRect(
            child: content,
          ),
        );
      }

      content = SizedBox(
        width: columnWidth,
        child: Align(
          alignment: alignmentFor(column),
          child: content,
        ),
      );
      return content;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _Table.rowHorizontalPadding,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          for (var i = 0; i < widget.columns.length; i++)
            columnFor(
              widget.columns[i],
              widget.columnWidths[i],
            ),
        ],
      ),
    );
  }

  @override
  bool get isExpanded => widget.isExpanded;

  @override
  void onExpandChanged(bool expanded) {}

  @override
  bool shouldShow() => widget.isShown;
}
