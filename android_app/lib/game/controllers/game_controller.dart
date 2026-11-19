import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_board.dart';

class GameState {
  final int score;
  final int movesLeft;
  final int targetScore;
  final int level;
  final List<List<GemTile>> grid;
  final GemTile? selectedTile;
  final bool isGameOver;
  final bool isLevelCleared;

  const GameState({
    required this.score,
    required this.movesLeft,
    required this.targetScore,
    required this.level,
    required this.grid,
    this.selectedTile,
    this.isGameOver = false,
    this.isLevelCleared = false,
  });

  GameState copyWith({
    int? score,
    int? movesLeft,
    int? targetScore,
    int? level,
    List<List<GemTile>>? grid,
    GemTile? selectedTile,
    bool clearSelected = false,
    bool? isGameOver,
    bool? isLevelCleared,
  }) {
    return GameState(
      score: score ?? this.score,
      movesLeft: movesLeft ?? this.movesLeft,
      targetScore: targetScore ?? this.targetScore,
      level: level ?? this.level,
      grid: grid ?? this.grid,
      selectedTile: clearSelected ? null : (selectedTile ?? this.selectedTile),
      isGameOver: isGameOver ?? this.isGameOver,
      isLevelCleared: isLevelCleared ?? this.isLevelCleared,
    );
  }
}

class GameController extends StateNotifier<GameState> {
  static const int rows = 7;
  static const int cols = 7;
  final Random _rng = Random();

  GameController() : super(_initialState()) {
    startLevel(1);
  }

  static GameState _initialState() {
    return const GameState(
      score: 0,
      movesLeft: 20,
      targetScore: 1000,
      level: 1,
      grid: [],
    );
  }

  void startLevel(int level) {
    final newGrid = _generateInitialGrid();
    state = GameState(
      score: 0,
      movesLeft: 20 + level * 2,
      targetScore: 1000 + level * 500,
      level: level,
      grid: newGrid,
      isGameOver: false,
      isLevelCleared: false,
    );
  }

  List<List<GemTile>> _generateInitialGrid() {
    return List.generate(rows, (r) {
      return List.generate(cols, (c) {
        return GemTile(row: r, col: c, type: GemType.random(_rng));
      });
    });
  }

  void onTileTapped(int r, int c) {
    if (state.isGameOver || state.isLevelCleared) return;

    final clickedTile = state.grid[r][c];

    if (state.selectedTile == null) {
      state = state.copyWith(selectedTile: clickedTile);
    } else {
      final prev = state.selectedTile!;
      final isAdjacent = (prev.row == r && (prev.col - c).abs() == 1) ||
          (prev.col == c && (prev.row - r).abs() == 1);

      if (isAdjacent) {
        _swapTiles(prev, clickedTile);
      } else {
        state = state.copyWith(selectedTile: clickedTile);
      }
    }
  }

  void _swapTiles(GemTile a, GemTile b) {
    final newGrid = List<List<GemTile>>.generate(
      rows,
      (r) => List<GemTile>.from(state.grid[r]),
    );

    // Swap types
    final tempType = newGrid[a.row][a.col].type;
    newGrid[a.row][a.col] = newGrid[a.row][a.col].copyWith(type: newGrid[b.row][b.col].type);
    newGrid[b.row][b.col] = newGrid[b.row][b.col].copyWith(type: tempType);

    final matchCount = _evaluateMatches(newGrid);
    final moves = state.movesLeft - 1;
    final newScore = state.score + (matchCount > 0 ? matchCount * 100 : 10);

    final isWin = newScore >= state.targetScore;
    final isLoss = !isWin && moves <= 0;

    state = state.copyWith(
      grid: newGrid,
      clearSelected: true,
      movesLeft: moves,
      score: newScore,
      isLevelCleared: isWin,
      isGameOver: isLoss,
    );
  }

  int _evaluateMatches(List<List<GemTile>> grid) {
    int matchesFound = 0;
    // Check horizontal matches
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols - 2; c++) {
        if (grid[r][c].type == grid[r][c + 1].type &&
            grid[r][c].type == grid[r][c + 2].type) {
          matchesFound += 3;
          // Respawn with random gem
          grid[r][c] = grid[r][c].copyWith(type: GemType.random(_rng));
          grid[r][c + 1] = grid[r][c + 1].copyWith(type: GemType.random(_rng));
          grid[r][c + 2] = grid[r][c + 2].copyWith(type: GemType.random(_rng));
        }
      }
    }
    return matchesFound;
  }
}

final gameProvider = StateNotifierProvider<GameController, GameState>((ref) {
  return GameController();
});
