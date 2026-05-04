import 'package:flutter/material.dart';

/// Paleta de cores centralizada do E-Metrics IoT.
///
/// Organizada em grupos semânticos para facilitar manutenção e rebranding.
/// Use sempre estas constantes em vez de `Color(0xFF...)` hardcoded nos widgets.
abstract final class AppColors {
  // ── Tema Escuro ──────────────────────────────────────────────────────────
  /// Fundo principal das telas no tema escuro.
  static const Color darkScaffold = Color(0xFF0F1419);

  /// Cor de superfície de cards e AppBar no tema escuro.
  static const Color darkSurface = Color(0xFF1A202C);

  /// Cor de bordas e separadores no tema escuro.
  static const Color darkOutline = Color(0xFF2D3748);

  /// Cor primária (ciano) no tema escuro.
  static const Color darkPrimary = Color(0xFF00D8FF);

  /// Cor secundária (âmbar) no tema escuro.
  static const Color darkSecondary = Color(0xFFFFB300);

  /// Cor terciária (verde) no tema escuro.
  static const Color darkTertiary = Color(0xFF00FF88);

  /// Cor de texto principal no tema escuro.
  static const Color darkTextPrimary = Color(0xFFE2E8F0);

  /// Cor de texto secundário no tema escuro.
  static const Color darkTextSecondary = Color(0xFFCBD5E0);

  /// Cor de texto terciário no tema escuro.
  static const Color darkTextTertiary = Color(0xFFA0AEC0);

  /// Cor de títulos no tema escuro.
  static const Color darkTextTitle = Color(0xFFF7FAFC);

  /// Cor de hints/placeholders no tema escuro.
  static const Color darkHint = Color(0xFF718096);

  // ── Tema Claro ───────────────────────────────────────────────────────────
  /// Fundo principal das telas no tema claro.
  static const Color lightScaffold = Color(0xFFF4F7FB);

  /// Cor de superfície de cards no tema claro.
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// Cor de fundo de cards no tema claro.
  static const Color lightCard = Color(0xFFFFFFFF);

  /// Cor de preenchimento de campos de texto no tema claro.
  static const Color lightInputFill = Color(0xFFFFFFFF);

  /// Cor de bordas no tema claro.
  static const Color lightOutline = Color(0xFF94A3B8);

  /// Cor de borda de campos de texto no tema claro.
  static const Color lightInputBorder = Color(0xFFB6C2D2);

  /// Cor primária (azul escuro) no tema claro.
  static const Color lightPrimary = Color(0xFF1E40AF);

  /// Cor secundária (azul médio) no tema claro.
  static const Color lightSecondary = Color(0xFF3B82F6);

  /// Cor terciária (verde escuro) no tema claro.
  static const Color lightTertiary = Color(0xFF059669);

  /// Cor de títulos no tema claro.
  static const Color lightTextTitle = Color(0xFF0F172A);

  /// Cor de texto de corpo no tema claro.
  static const Color lightTextBody = Color(0xFF1E293B);

  /// Cor de texto pequeno no tema claro.
  static const Color lightTextSmall = Color(0xFF334155);

  /// Cor de rótulos de campo no tema claro.
  static const Color lightLabel = Color(0xFF334155);

  /// Cor de hints/placeholders no tema claro.
  static const Color lightHint = Color(0xFF64748B);

  /// Cor de ícones/texto não selecionados na nav bar (tema claro).
  static const Color lightUnselected = Color(0xFF475569);

  // ── Estados de conexão MQTT ──────────────────────────────────────────────
  /// Indica erro ou falha de conexão.
  static const Color statusError = Color(0xFFDC2626);

  /// Indica estado de alerta ou conectando.
  static const Color statusWarning = Color(0xFFD97706);

  /// Indica operação normal / conectado com leituras recentes.
  static const Color statusSuccess = Color(0xFF15803D);

  /// Indica estado ocioso / desconectado.
  static const Color statusIdle = Color(0xFF64748B);

  /// Cor de texto para mensagem de erro ao carregar dados.
  static const Color errorDataText = Color(0xFFFFC300);

  // ── Métricas elétricas (cards do dashboard) ──────────────────────────────
  /// Potência aparente (VA).
  static const Color metricApparent = Color(0xFF10B981);

  /// Potência ativa (W).
  static const Color metricActive = Color(0xFFF59E0B);

  /// Potência reativa (VAr).
  static const Color metricReactive = Color(0xFF0EA5E9);

  /// Fator de potência (adimensional).
  static const Color metricPf = Color(0xFF6366F1);

  /// Tensão (V).
  static const Color metricVoltage = Color(0xFF3B82F6);

  /// Corrente (A).
  static const Color metricCurrent = Color(0xFF06B6D4);

  /// Energia acumulada (kWh).
  static const Color metricEnergy = Color(0xFF8B5CF6);

  /// Frequência (Hz).
  static const Color metricFrequency = Color(0xFF22C55E);

  // ── Card de previsão (forecast) ─────────────────────────────────────────
  /// Cor de borda do card de previsão.
  static const Color forecastBorder = Color(0xFF38BDF8);

  /// Fundo dos chips de previsão no tema escuro.
  static const Color forecastChipDark = Color(0xFF111827);

  // ── Sombras ──────────────────────────────────────────────────────────────
  /// Sombra padrão no tema escuro.
  static const Color shadowDark = Color(0x4D000000);

  /// Sombra padrão no tema claro.
  static const Color shadowLight = Color(0x0A000000);
}
