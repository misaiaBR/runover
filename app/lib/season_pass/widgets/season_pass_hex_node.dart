import 'package:flutter/material.dart';

/// Nó hexagonal da trilha do Passe de Temporada.
///
/// Recebe o conteúdo ([label]), a cor de fundo e o tamanho. A forma vem do
/// [SeasonPassHexClipper].
class SeasonPassHexNode extends StatelessWidget {
  const SeasonPassHexNode({
    super.key,
    required this.label,
    required this.color,
    required this.size,
  });

  final Widget label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const SeasonPassHexClipper(),
      child: Container(
        width: size,
        height: size,
        color: color,
        alignment: Alignment.center,
        child: label,
      ),
    );
  }
}

/// Recorte hexagonal: cantos chanfrados em cima/embaixo, pontas nas laterais.
class SeasonPassHexClipper extends CustomClipper<Path> {
  const SeasonPassHexClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * .25, size.height * .03)
      ..lineTo(size.width * .75, size.height * .03)
      ..lineTo(size.width, size.height * .5)
      ..lineTo(size.width * .75, size.height * .97)
      ..lineTo(size.width * .25, size.height * .97)
      ..lineTo(0, size.height * .5)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
