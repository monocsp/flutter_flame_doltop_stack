import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flame_breath_journey_game/game/breath_game_blueprint.dart';
import 'package:flutter_flame_breath_journey_game/game/breath_preview_game.dart';

class BreathJourneyHomeScreen extends StatelessWidget {
  const BreathJourneyHomeScreen({
    super.key,
    this.blueprint = BreathGameBlueprint.starter,
  });

  final BreathGameBlueprint blueprint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          buildBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool isCompact = constraints.maxWidth < 860;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: isCompact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            buildHeader(),
                            const SizedBox(height: 18),
                            buildPreviewCard(),
                            const SizedBox(height: 18),
                            buildConceptSection(),
                            const SizedBox(height: 18),
                            buildFoundationSection(),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            buildHeader(),
                            const SizedBox(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(flex: 6, child: buildPreviewCard()),
                                const SizedBox(width: 18),
                                Expanded(
                                  flex: 5,
                                  child: buildFoundationSection(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            buildConceptSection(),
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'THIRD GAME',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
            color: Color(0xFFFFD7A1),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          blueprint.title,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            height: 1.05,
            color: Color(0xFFF7F3E9),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          blueprint.subtitle,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Color(0xFFE3D7C8),
          ),
        ),
      ],
    );
  }

  Widget buildPreviewCard() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF10151D).withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xFFF7F3E9).withValues(alpha: 0.08),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Prototype Board',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Color(0xFFFFD7A1),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '호흡 리듬이 커졌다 작아지는 느낌을 먼저 시각적으로 잡아둔 프리뷰입니다.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Color(0xFFD9CAB3),
              ),
            ),
            const SizedBox(height: 14),
            AspectRatio(
              aspectRatio: BreathPreviewGame.boardAspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E14),
                    border: Border.all(
                      color: const Color(0xFFF7F3E9).withValues(alpha: 0.08),
                    ),
                  ),
                  child: GameWidget<BreathPreviewGame>(
                    game: BreathPreviewGame(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildConceptSection() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF10151D).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xFFF7F3E9).withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Concept Candidates',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Color(0xFFFFD7A1),
              ),
            ),
            const SizedBox(height: 14),
            ...blueprint.concepts.map(buildConceptCard),
          ],
        ),
      ),
    );
  }

  Widget buildConceptCard(BreathConcept concept) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF171D27),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            concept.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFFF7F3E9),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            concept.tagline,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFFD7A1),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            concept.summary,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xFFD9CAB3),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildFoundationSection() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF10151D).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xFFF7F3E9).withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Foundation Ready',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Color(0xFFFFD7A1),
              ),
            ),
            const SizedBox(height: 14),
            ...blueprint.foundationScopes.map(buildCheckRow),
            const SizedBox(height: 18),
            const Text(
              'Next Steps',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Color(0xFFFFD7A1),
              ),
            ),
            const SizedBox(height: 12),
            ...blueprint.nextSteps.map(buildNextStepCard),
          ],
        ),
      ),
    );
  }

  Widget buildCheckRow(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: Color(0xFF7ADAA5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFFD9CAB3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildNextStepCard(String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF171D27),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFFFD7A1)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF7F3E9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildBackground() {
    return Stack(
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: <double>[0.0, 0.32, 1.0],
              colors: <Color>[
                Color(0xFF1A2740),
                Color(0xFF273A53),
                Color(0xFF365C72),
              ],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(
          top: -80,
          right: -30,
          child: IgnorePointer(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFE7B8).withValues(alpha: 0.10),
              ),
            ),
          ),
        ),
        Positioned(
          left: -40,
          bottom: -30,
          child: IgnorePointer(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF78C0E0).withValues(alpha: 0.10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
