import 'package:flutter/material.dart';

/// Dourado da faixa do passe.
///
/// Convenção já usada nas telas do passe (`PassSummary` em `pass_screen.dart`):
/// o tema do app não tem dourado na paleta, então o passe premium usa estes
/// valores fixos nas duas claridades (igual ao cartão roxo do resumo, que é
/// escuro no tema claro e no escuro).
const seasonPassGold = Color(0xFFFFC93C);
const seasonPassGoldBg = Color(0xFF1E1C16);
const seasonPassGoldBorder = Color(0xFF6B5A1E);

/// Texto legível sobre o dourado (botões e selos preenchidos).
const seasonPassOnGold = Color(0xFF3A2A00);
