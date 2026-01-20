-- Migration: Adiciona coluna rejection_reason em daily_plan_ai
-- Data: 2026-01-17
-- Descrição: Registra o motivo quando um treino é rejeitado pela validação

ALTER TABLE daily_plan_ai ADD COLUMN rejection_reason TEXT;
