import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/onboarding.dart';
import '../state/app_state.dart';
import '../widgets/app_drawer.dart';
import '../widgets/cookie_consent.dart';
import '../widgets/game_nav.dart';
import '../widgets/guided_tour.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'ranking_screen.dart';
import 'runs_screen.dart';
import 'teams_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _menuKey = GlobalKey();
  final _startKey = GlobalKey();
  final _tabsKey = GlobalKey();

  bool _touring = false;
  bool _tourChecked = false;
  int _seenTourRequests = 0;

  /// Abas com aviso real. Hoje é só a Equipe, e o aviso é convite de equipe
  /// ainda não respondido — o ponto nunca aparece decorativo.
  final Set<int> _alerted = {};
  bool _badgeBusy = false;

  /// O gesto de abrir o menu lateral. A casca é dona do `endDrawer`, então é
  /// ela quem o oferece — e ele só vai para as duas telas onde a pessoa chega
  /// sem outro caminho para o menu: a home (HUD) e o perfil. Corridas, Ranking
  /// e Equipe ficam sem o botão; ali quem navega é a barra de baixo.
  void _openMenu() => _scaffoldKey.currentState?.openEndDrawer();

  late final _screens = [
    HomeScreen(
      onOpenMenu: _openMenu,
      menuKey: _menuKey,
      startKey: _startKey,
    ),
    const RunsScreen(),
    const RankingScreen(),
    const TeamsScreen(),
    ProfileScreen(onOpenMenu: _openMenu, onOpenTab: _select),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      maybeShowCookieBanner(context);
      _refreshTeamAlert();
    });
  }

  /// O ponto de aviso da Equipe são convites ainda não respondidos. A leitura
  /// falhou? O ponto fica como estava — aviso a menos não quebra a tela.
  Future<void> _refreshTeamAlert() async {
    if (_badgeBusy || !mounted) return;
    _badgeBusy = true;
    try {
      final invites = await context.read<AppState>().api.getMyInvites();
      if (mounted) {
        setState(() {
          if (invites.isEmpty) {
            _alerted.remove(kTeamTabIndex);
          } else {
            _alerted.add(kTeamTabIndex);
          }
        });
      }
    } catch (_) {
      // Sem resposta, nenhum aviso novo.
    } finally {
      _badgeBusy = false;
    }
  }

  void _select(int index) {
    final left = _index == kTeamTabIndex && index != kTeamTabIndex;
    setState(() => _index = index);
    // Saiu da Equipe: se o convite foi respondido lá, o ponto tem de sumir.
    if (left) _refreshTeamAlert();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App voltou ao primeiro plano: renova o "online" da equipe e o aviso.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AppState>().pingPresence();
      _refreshTeamAlert();
    }
  }

  List<TourStep> get _steps => [
    TourStep(
      targetKey: _menuKey,
      title: 'Menu lateral',
      text: 'Toque aqui para abrir perfil, abas, tutorial e saída.',
    ),
    TourStep(
      targetKey: _startKey,
      title: 'Iniciar corrida',
      text: 'Toque para começar a registrar um trajeto e conquistar territórios.',
    ),
    TourStep(
      targetKey: _tabsKey,
      title: 'Navegação',
      text: 'Alterne entre Início, Corridas, Ranking e Equipe.',
    ),
  ];

  Future<void> _finishTour() async {
    try {
      await OnboardingStore.markSeen();
    } catch (_) {
      // Segue mesmo assim; o tour pode reaparecer.
    }
    if (mounted) setState(() => _touring = false);
  }

  void _maybeStartTour() {
    if (_touring || !mounted) return;
    setState(() {
      _index = 0;
      _touring = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final requests = context.watch<AppState>().tourRequests;
    if (requests != _seenTourRequests) {
      _seenTourRequests = requests;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartTour());
    } else if (!_tourChecked) {
      _tourChecked = true;
      OnboardingStore.seen().then((seen) {
        if (!seen && mounted) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _maybeStartTour(),
          );
        }
      }).catchError((_) {});
    }
    final wide = MediaQuery.sizeOf(context).width >= kAccountChipMinWidth;
    final pages = Stack(
      children: [
        _screens[_index],
        if (_touring) GuidedTour(steps: _steps, onFinish: _finishTour),
      ],
    );
    final navBar = GameNavBar(
      key: _tabsKey,
      index: _index,
      alerted: _alerted,
      onSelect: _select,
    );
    return Scaffold(
      key: _scaffoldKey,
      // Um menu só — e ele cai do lado onde está o botão que o abre.
      endDrawer: AppDrawer(selectedIndex: _index, onSelectTab: _select),
      body: pages,
      // A barra é a navegação em qualquer largura. Na janela larga o canto que
      // sobra à esquerda é da ficha da conta: ela fica ao lado da barra, não
      // em cima, porque empilhar as duas tiraria altura da página por nada. O
      // toque na ficha abre o perfil, onde a presença se mostra e se troca.
      bottomNavigationBar: wide
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    AccountChip(onTap: () => _select(kProfileTabIndex)),
                    const SizedBox(width: 12),
                    Expanded(child: navBar),
                  ],
                ),
              ),
            )
          : navBar,
    );
  }
}
