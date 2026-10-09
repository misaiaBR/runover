class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint(this.lat, this.lng);

  factory LatLngPoint.fromJson(Map<String, dynamic> j) =>
      LatLngPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
}

class Territory {
  final String id;
  final String name;
  final List<LatLngPoint> coordinates;
  final LatLngPoint center;
  final double radiusM;
  final String status; // "disponivel" | "conquistado"
  final String? ownerType; // "user" | "team"
  final String? ownerDisplay;
  final int takeovers;

  const Territory({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.center,
    required this.radiusM,
    required this.status,
    required this.ownerType,
    required this.ownerDisplay,
    this.takeovers = 0,
  });

  bool get isFree => status == 'disponivel';
  bool get isOwnedByTeam => ownerType == 'team';

  factory Territory.fromJson(Map<String, dynamic> j) => Territory(
    id: j['id'],
    name: j['name'],
    coordinates: (j['coordinates'] as List)
        .map((c) => LatLngPoint.fromJson(c))
        .toList(),
    center: LatLngPoint.fromJson(j['center']),
    radiusM: (j['radius_m'] as num).toDouble(),
    status: j['status'],
    ownerType: j['owner_type'],
    ownerDisplay: j['owner_display'],
    takeovers: (j['takeovers'] as num?)?.toInt() ?? 0,
  );
}

class OwnerHistoryEntry {
  final String ownerType;
  final String ownerDisplay;
  final DateTime conqueredAt;

  const OwnerHistoryEntry({
    required this.ownerType,
    required this.ownerDisplay,
    required this.conqueredAt,
  });

  factory OwnerHistoryEntry.fromJson(Map<String, dynamic> j) =>
      OwnerHistoryEntry(
        ownerType: j['owner_type'],
        ownerDisplay: j['owner_display'],
        conqueredAt: DateTime.parse(j['conquered_at']),
      );
}

class TerritoryDetail extends Territory {
  final DateTime? conquestAt;
  final int pointsValue;
  final List<OwnerHistoryEntry> history;
  final int? ownerPaceSecondsPerKm; // marca a bater — ritmo do dono
  final double? ownerDistanceM; // marca a bater — distância do dono
  final int? ownerDurationSeconds; // tempo máximo do desafio de distância

  const TerritoryDetail({
    required super.id,
    required super.name,
    required super.coordinates,
    required super.center,
    required super.radiusM,
    required super.status,
    required super.ownerType,
    required super.ownerDisplay,
    super.takeovers,
    required this.conquestAt,
    required this.pointsValue,
    this.history = const [],
    this.ownerPaceSecondsPerKm,
    this.ownerDistanceM,
    this.ownerDurationSeconds,
  });

  factory TerritoryDetail.fromJson(Map<String, dynamic> j) => TerritoryDetail(
    id: j['id'],
    name: j['name'],
    coordinates: (j['coordinates'] as List)
        .map((c) => LatLngPoint.fromJson(c))
        .toList(),
    center: LatLngPoint.fromJson(j['center']),
    radiusM: (j['radius_m'] as num).toDouble(),
    status: j['status'],
    ownerType: j['owner_type'],
    ownerDisplay: j['owner_display'],
    takeovers: (j['takeovers'] as num?)?.toInt() ?? 0,
    conquestAt: j['conquered_at'] != null
        ? DateTime.parse(j['conquered_at'])
        : null,
    pointsValue: j['points_value'],
    history: ((j['history'] as List?) ?? const [])
        .map((e) => OwnerHistoryEntry.fromJson(e))
        .toList(),
    ownerPaceSecondsPerKm: j['owner_pace_seconds_per_km'] as int?,
    ownerDistanceM: (j['owner_distance_m'] as num?)?.toDouble(),
    ownerDurationSeconds: j['owner_duration_seconds'] as int?,
  );
}

/// Território selvagem estilo Pokémon GO: aparece sozinho no mapa.
class WildSpawn {
  final String key;
  final LatLngPoint center;
  final double radiusM;
  final int relevance;
  final String rarity; // "comum" | "raro" | "épico"
  final DateTime spawnedAt;
  final DateTime expiresAt;

  const WildSpawn({
    required this.key,
    required this.center,
    required this.radiusM,
    required this.relevance,
    required this.rarity,
    required this.spawnedAt,
    required this.expiresAt,
  });

  factory WildSpawn.fromJson(Map<String, dynamic> j) => WildSpawn(
    key: j['key'],
    center: LatLngPoint.fromJson(j['center']),
    radiusM: (j['radius_m'] as num).toDouble(),
    relevance: j['relevance'] as int,
    rarity: j['rarity'],
    spawnedAt: DateTime.parse(j['spawned_at']),
    expiresAt: DateTime.parse(j['expires_at']),
  );
}

class UserProfile {
  final String id;
  final String fullName;
  final String username;
  final String email;
  final String? photoUrl;
  final DateTime? memberSince; // "Membro desde" (created_at da API).
  final int totalScore;
  final int territoriesCount;
  final int? rankPosition;
  final String? teamName;
  final int level; // RF11 / RN10
  final double levelProgress; // 0..1 até o próximo nível
  final int pointsToNextLevel;
  final bool isPublic; // RF05
  final bool shareActivities;
  final String? pronouns;
  final String? accentColor; // Cor de destaque gratuita (#RRGGBB).
  final int coinBalance;
  final int playSeconds; // RF19 — tempo de jogo
  // Preferências de treino (privadas, editáveis no perfil)
  final String distanceUnits; // "km" | "mi"
  final int? weeklyFrequency; // dias/semana (1..7)
  final List<String> trainingDays; // ex. ["seg","qua","sex"]
  final String? activityLevel;
  // Mercado interno: saldo + cosméticos equipados + mural (via API).
  final int coinsBalance;
  final String? equippedAvatar;
  final String? equippedFrame;
  final String? equippedEffect;
  final String? equippedBanner;
  final String? equippedNameStyle;
  final List<String> equippedEmoticons;
  final List<String> muralWidgets;

  const UserProfile({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.photoUrl,
    this.memberSince,
    required this.totalScore,
    required this.territoriesCount,
    required this.rankPosition,
    required this.teamName,
    required this.level,
    required this.levelProgress,
    required this.pointsToNextLevel,
    required this.isPublic,
    required this.shareActivities,
    this.pronouns,
    this.accentColor,
    this.coinBalance = 0,
    required this.playSeconds,
    this.distanceUnits = 'km',
    this.weeklyFrequency,
    this.trainingDays = const [],
    this.activityLevel,
    this.coinsBalance = 0,
    this.equippedAvatar,
    this.equippedFrame,
    this.equippedEffect,
    this.equippedBanner,
    this.equippedNameStyle,
    this.equippedEmoticons = const [],
    this.muralWidgets = const [
      'emoticons',
      'conquistas',
      'atividades',
      'estatisticas',
    ],
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id: j['id'],
    fullName: j['full_name'],
    username: j['username'],
    email: j['email'],
    photoUrl: j['photo_url'],
    memberSince: j['created_at'] == null
        ? null
        : DateTime.tryParse('${j['created_at']}'),
    totalScore: j['total_score'],
    territoriesCount: j['territories_count'],
    rankPosition: j['rank_position'],
    teamName: j['team_name'],
    level: j['level'] ?? 1,
    levelProgress: (j['level_progress'] as num?)?.toDouble() ?? 0,
    pointsToNextLevel: j['points_to_next_level'] ?? 0,
    isPublic: j['is_public'] ?? true,
    shareActivities: j['share_activities'] ?? true,
    pronouns: j['pronouns'],
    accentColor: j['accent_color'],
    coinBalance: j['coin_balance'] ?? 0,
    playSeconds: j['play_seconds'] ?? 0,
    distanceUnits: j['distance_units'] ?? 'km',
    weeklyFrequency: j['weekly_frequency'],
    trainingDays: [
      for (final d in (j['training_days'] as List?) ?? const []) '$d',
    ],
    activityLevel: j['activity_level'],
    coinsBalance: (j['coins_balance'] as num?)?.toInt() ?? 0,
    equippedAvatar: j['equipped_avatar'],
    equippedFrame: j['equipped_frame'],
    equippedEffect: j['equipped_effect'],
    equippedBanner: j['equipped_banner'],
    equippedNameStyle: j['equipped_name_style'],
    equippedEmoticons: [
      for (final e in (j['equipped_emoticons'] as List?) ?? const []) '$e',
    ],
    muralWidgets: [
      for (final w in (j['mural_widgets'] as List?) ??
          const ['emoticons', 'conquistas', 'atividades', 'estatisticas'])
        '$w',
    ],
  );
}

/// RF17 — perfil público de outro jogador (o back-end só devolve dados
/// públicos, e nega com 403 se o perfil estiver privado — RF05/RN13).
class PublicProfile {
  final String username;
  final String? photoUrl;
  final int totalScore;
  final int territoriesCount;
  final int? rankPosition;
  final String? teamName;
  final int level;
  final double levelProgress;
  final int pointsToNextLevel;
  final String? equippedAvatar;
  final String? equippedFrame;
  final String? equippedEffect;
  final String? equippedBanner;
  final String? equippedNameStyle;
  final List<String> equippedEmoticons;
  final List<String> muralWidgets;
  final String? accentColor;

  const PublicProfile({
    required this.username,
    required this.photoUrl,
    required this.totalScore,
    required this.territoriesCount,
    required this.rankPosition,
    required this.teamName,
    required this.level,
    required this.levelProgress,
    required this.pointsToNextLevel,
    this.equippedAvatar,
    this.equippedFrame,
    this.equippedEffect,
    this.equippedBanner,
    this.equippedNameStyle,
    this.equippedEmoticons = const [],
    this.muralWidgets = const [
      'emoticons',
      'conquistas',
      'atividades',
      'estatisticas',
    ],
    this.accentColor,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> j) => PublicProfile(
    username: j['username'],
    photoUrl: j['photo_url'],
    totalScore: j['total_score'],
    territoriesCount: j['territories_count'],
    rankPosition: j['rank_position'],
    teamName: j['team_name'],
    level: j['level'] ?? 1,
    levelProgress: (j['level_progress'] as num?)?.toDouble() ?? 0,
    pointsToNextLevel: j['points_to_next_level'] ?? 0,
    equippedAvatar: j['equipped_avatar'],
    equippedFrame: j['equipped_frame'],
    equippedEffect: j['equipped_effect'],
    equippedBanner: j['equipped_banner'],
    equippedNameStyle: j['equipped_name_style'],
    equippedEmoticons: [
      for (final e in (j['equipped_emoticons'] as List?) ?? const []) '$e',
    ],
    accentColor: j['accent_color'],
    muralWidgets: [
      for (final w in (j['mural_widgets'] as List?) ??
          const ['emoticons', 'conquistas', 'atividades', 'estatisticas'])
        '$w',
    ],
  );
}

/// Item do mercado interno (via API: GET /shop/catalog).
class ShopItem {
  final String id;
  final String category;
  final String name;
  final int price;
  final String scope; // "user" | "team" (loja da equipe, preços altos)
  final Map<String, dynamic> payload;

  const ShopItem({
    required this.id,
    required this.category,
    required this.name,
    required this.price,
    this.scope = 'user',
    required this.payload,
  });

  factory ShopItem.fromJson(Map<String, dynamic> j) => ShopItem(
    id: j['id'],
    category: j['category'],
    name: j['name'],
    price: (j['price'] as num).toInt(),
    scope: j['scope'] ?? 'user',
    payload: Map<String, dynamic>.from(j['payload'] ?? const {}),
  );
}

/// Carteira + inventário do mercado (via API).
class Inventory {
  final List<String> owned;
  final String? equippedAvatar;
  final String? equippedFrame;
  final String? equippedEffect;
  final String? equippedBanner;
  final String? equippedNameStyle;
  final List<String> equippedEmoticons;

  const Inventory({
    this.owned = const [],
    this.equippedAvatar,
    this.equippedFrame,
    this.equippedEffect,
    this.equippedBanner,
    this.equippedNameStyle,
    this.equippedEmoticons = const [],
  });

  factory Inventory.fromJson(Map<String, dynamic> j) => Inventory(
    owned: [for (final o in (j['owned'] as List?) ?? const []) '$o'],
    equippedAvatar: j['equipped_avatar'],
    equippedFrame: j['equipped_frame'],
    equippedEffect: j['equipped_effect'],
    equippedBanner: j['equipped_banner'],
    equippedNameStyle: j['equipped_name_style'],
    equippedEmoticons: [
      for (final e in (j['equipped_emoticons'] as List?) ?? const []) '$e',
    ],
  );

  bool isEquipped(ShopItem item) {
    return switch (item.category) {
      'avatar' => equippedAvatar == item.id,
      'frame' => equippedFrame == item.id,
      'effect' => equippedEffect == item.id,
      'banner' => equippedBanner == item.id,
      'name_style' => equippedNameStyle == item.id,
      'emoticon' => equippedEmoticons.any(
        (e) => (item.payload['emoji'] as List? ?? const []).contains(e),
      ),
      _ => false,
    };
  }
}

/// Insígnia do catálogo de conquistas (via API: GET /badges).
///
/// A regra mora no servidor (`backend/app/services/badges.py`): `metric` é a
/// métrica observada, `threshold` o limiar e `earnedAt` a data do registro.
class Insignia {
  final String id;
  final String name;
  final String description;
  final String icon; // run | flag | route | team | level
  final String metric;
  final double threshold;
  final double progress;
  final bool earned;
  final DateTime? earnedAt;

  const Insignia({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.metric,
    required this.threshold,
    required this.progress,
    required this.earned,
    this.earnedAt,
  });

  bool get isLevelReward => metric == 'level';

  factory Insignia.fromJson(Map<String, dynamic> j) => Insignia(
    id: '${j['id']}',
    name: '${j['name']}',
    description: '${j['description']}',
    icon: '${j['icon'] ?? 'verified'}',
    metric: '${j['metric'] ?? ''}',
    threshold: (j['threshold'] as num?)?.toDouble() ?? 0,
    progress: (j['progress'] as num?)?.toDouble() ?? 0,
    earned: j['earned'] == true,
    earnedAt: j['earned_at'] == null ? null : DateTime.parse('${j['earned_at']}'),
  );
}

class TeamMemberInfo {
  final String username;
  final String? photoUrl;
  final bool isAdmin;
  final bool isOnline;
  const TeamMemberInfo({
    required this.username,
    required this.photoUrl,
    this.isAdmin = false,
    this.isOnline = false,
  });

  factory TeamMemberInfo.fromJson(Map<String, dynamic> j) => TeamMemberInfo(
    username: j['username'],
    photoUrl: j['photo_url'],
    isAdmin: j['is_admin'] == true,
    isOnline: j['is_online'] == true,
  );
}

class TeamJoinRequestInfo {
  final String id;
  final String username;
  final String? photoUrl;
  final String createdAt;
  const TeamJoinRequestInfo({
    required this.id,
    required this.username,
    required this.photoUrl,
    required this.createdAt,
  });

  factory TeamJoinRequestInfo.fromJson(Map<String, dynamic> j) =>
      TeamJoinRequestInfo(
        id: j['id'],
        username: j['username'],
        photoUrl: j['photo_url'],
        createdAt: j['created_at'] ?? '',
      );
}

class TeamSummary {
  final String id;
  final String name;
  final String? photoUrl;
  final String creatorUsername;
  final int memberCount;
  final int territoriesCount;
  final DateTime? createdAt;
  // Cosméticos da loja visíveis na lista e no ranking.
  final String? equippedAvatar;
  final String? equippedFrame;
  final String? equippedBanner;
  final String? equippedNameStyle;

  const TeamSummary({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.creatorUsername,
    required this.memberCount,
    this.territoriesCount = 0,
    this.createdAt,
    this.equippedAvatar,
    this.equippedFrame,
    this.equippedBanner,
    this.equippedNameStyle,
  });

  factory TeamSummary.fromJson(Map<String, dynamic> j) => TeamSummary(
    id: j['id'],
    name: j['name'],
    photoUrl: j['photo_url'],
    creatorUsername: j['creator_username'],
    memberCount: j['member_count'],
    territoriesCount: (j['territories_count'] as num?)?.toInt() ?? 0,
    createdAt: j['created_at'] == null ? null : DateTime.parse(j['created_at']),
    equippedAvatar: j['equipped_avatar'],
    equippedFrame: j['equipped_frame'],
    equippedBanner: j['equipped_banner'],
    equippedNameStyle: j['equipped_name_style'],
  );
}

class TeamDetail extends TeamSummary {
  final List<TeamMemberInfo> members;
  final int totalScore;
  final int level; // RF11 / RN10
  final double levelProgress;
  final int pointsToNextLevel;
  final bool isOwner;
  final bool isAdmin;
  final String? myRequest;
  final List<TeamJoinRequestInfo> pendingRequests;
  final int onlineCount;
  // Loja da equipe: cofre (soma dos pontos dos integrantes − já gasto).
  final int teamBalance;
  final int teamSpent;
  final String? equippedEffect;

  const TeamDetail({
    required super.id,
    required super.name,
    super.photoUrl,
    required super.creatorUsername,
    required super.memberCount,
    required super.territoriesCount,
    super.createdAt,
    super.equippedAvatar,
    super.equippedFrame,
    super.equippedBanner,
    super.equippedNameStyle,
    required this.members,
    required this.totalScore,
    required this.level,
    required this.levelProgress,
    required this.pointsToNextLevel,
    this.isOwner = false,
    this.isAdmin = false,
    this.myRequest,
    this.pendingRequests = const [],
    this.onlineCount = 0,
    this.teamBalance = 0,
    this.teamSpent = 0,
    this.equippedEffect,
  });

  factory TeamDetail.fromJson(Map<String, dynamic> j) => TeamDetail(
    id: j['id'],
    name: j['name'],
    photoUrl: j['photo_url'],
    creatorUsername: j['creator_username'],
    memberCount: j['member_count'],
    createdAt: j['created_at'] == null ? null : DateTime.parse(j['created_at']),
    members: (j['members'] as List)
        .map((m) => TeamMemberInfo.fromJson(m))
        .toList(),
    totalScore: j['total_score'],
    territoriesCount: j['territories_count'],
    level: j['level'] ?? 1,
    levelProgress: (j['level_progress'] as num?)?.toDouble() ?? 0,
    pointsToNextLevel: j['points_to_next_level'] ?? 0,
    isOwner: j['is_owner'] == true,
    isAdmin: j['is_admin'] == true,
    myRequest: j['my_request'],
    pendingRequests: (j['pending_requests'] as List? ?? const [])
        .map((r) => TeamJoinRequestInfo.fromJson(r))
        .toList(),
    onlineCount: j['online_count'] ?? 0,
    teamBalance: (j['team_balance'] as num?)?.toInt() ?? 0,
    teamSpent: (j['team_spent'] as num?)?.toInt() ?? 0,
    equippedAvatar: j['equipped_avatar'],
    equippedFrame: j['equipped_frame'],
    equippedEffect: j['equipped_effect'],
    equippedBanner: j['equipped_banner'],
    equippedNameStyle: j['equipped_name_style'],
  );
}

/// Cofre + inventário da loja da equipe (via API).
class TeamWallet {
  final int balance;
  final int spentPoints;
  final int membersPoints;

  const TeamWallet({
    required this.balance,
    required this.spentPoints,
    required this.membersPoints,
  });

  factory TeamWallet.fromJson(Map<String, dynamic> j) => TeamWallet(
    balance: (j['balance'] as num).toInt(),
    spentPoints: (j['spent_points'] as num).toInt(),
    membersPoints: (j['members_points'] as num).toInt(),
  );
}

class TeamInventory {
  final List<String> owned;
  final String? equippedAvatar;
  final String? equippedFrame;
  final String? equippedEffect;
  final String? equippedBanner;
  final String? equippedNameStyle;

  const TeamInventory({
    this.owned = const [],
    this.equippedAvatar,
    this.equippedFrame,
    this.equippedEffect,
    this.equippedBanner,
    this.equippedNameStyle,
  });

  factory TeamInventory.fromJson(Map<String, dynamic> j) => TeamInventory(
    owned: [for (final o in (j['owned'] as List?) ?? const []) '$o'],
    equippedAvatar: j['equipped_avatar'],
    equippedFrame: j['equipped_frame'],
    equippedEffect: j['equipped_effect'],
    equippedBanner: j['equipped_banner'],
    equippedNameStyle: j['equipped_name_style'],
  );

  bool isEquipped(ShopItem item) {
    return switch (item.category) {
      'avatar' => equippedAvatar == item.id,
      'frame' => equippedFrame == item.id,
      'effect' => equippedEffect == item.id,
      'banner' => equippedBanner == item.id,
      'name_style' => equippedNameStyle == item.id,
      _ => false,
    };
  }
}

class RankingEntry {
  final int position;
  final String ownerType; // "user" | "team"
  final String name;
  final String? photoUrl;
  final int totalScore;
  final int territoriesCount;
  final int level; // RF11 / RN10
  // Cosméticos da loja equipados (foto, nome e cards do ranking).
  final String? equippedAvatar;
  final String? equippedFrame;
  final String? equippedEffect;
  final String? equippedBanner;
  final String? equippedNameStyle;
  final String? accentColor;

  const RankingEntry({
    required this.position,
    required this.ownerType,
    required this.name,
    this.photoUrl,
    required this.totalScore,
    required this.territoriesCount,
    required this.level,
    this.equippedAvatar,
    this.equippedFrame,
    this.equippedEffect,
    this.equippedBanner,
    this.equippedNameStyle,
    this.accentColor,
  });

  factory RankingEntry.fromJson(Map<String, dynamic> j) => RankingEntry(
    position: j['position'],
    ownerType: j['owner_type'],
    name: j['name'],
    photoUrl: j['photo_url'],
    totalScore: j['total_score'],
    territoriesCount: j['territories_count'],
    level: j['level'] ?? 1,
    equippedAvatar: j['equipped_avatar'],
    equippedFrame: j['equipped_frame'],
    equippedEffect: j['equipped_effect'],
    equippedBanner: j['equipped_banner'],
    equippedNameStyle: j['equipped_name_style'],
    accentColor: j['accent_color'],
  );
}

class HistoryEntry {
  final String? territoryName;
  final int delta;
  final String reason;
  final DateTime createdAt;

  const HistoryEntry({
    required this.territoryName,
    required this.delta,
    required this.reason,
    required this.createdAt,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    territoryName: j['territory_name'],
    delta: j['delta'],
    reason: j['reason'],
    createdAt: DateTime.parse(j['created_at']),
  );
}

class NotificationEntry {
  final String id;
  final String message;
  final String type;
  final bool isRead;
  final DateTime createdAt;

  const NotificationEntry({
    required this.id,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationEntry.fromJson(Map<String, dynamic> j) =>
      NotificationEntry(
        id: j['id'],
        message: j['message'],
        type: j['type'],
        isRead: j['is_read'],
        createdAt: DateTime.parse(j['created_at']),
      );
}
