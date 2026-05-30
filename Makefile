# ============================================================
#  Makefile — Black Linux Build System
# ============================================================

SHELL       := /usr/bin/env bash
BUILD_DIR   := /opt/blacklinux-build
OUTPUT_DIR  := /opt/blacklinux-output
LOG         := /var/log/blacklinux-build.log
SCRIPTS     := $(CURDIR)/scripts
CONFIGS     := $(CURDIR)/configs
THEME       := $(CURDIR)/theme

.PHONY: all clean help check deps kernel rootfs iso install-to-disk \
        strata-init theme-only lang-only lkrg-only

# ── По умолчанию: полная сборка ───────────────────────────────
all: check deps kernel rootfs iso
	@echo ""
	@echo "  ╔══════════════════════════════════════╗"
	@echo "  ║   Black Linux собран успешно!        ║"
	@echo "  ║   Образ: $(OUTPUT_DIR)/              ║"
	@echo "  ╚══════════════════════════════════════╝"

# ── Проверка прав ─────────────────────────────────────────────
check:
	@[ "$$(id -u)" = "0" ] || { echo "  [!] Нужны права root: sudo make"; exit 1; }
	@echo "  [✓] Права root подтверждены"

# ── Установка зависимостей хоста ─────────────────────────────
deps:
	@echo "  [→] Установка зависимостей..."
	@apt-get update -qq && apt-get install -y --no-install-recommends \
	    debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
	    mtools dosfstools curl wget git build-essential bc flex bison \
	    libssl-dev libelf-dev libncurses-dev dwarves cpio rsync \
	    python3 python3-pip pciutils lshw jq aria2 2>>"$(LOG)"
	@echo "  [✓] Зависимости установлены"

# ── Только ядро ───────────────────────────────────────────────
kernel:
	@echo "  [→] Получение и сборка ядра..."
	@bash $(CURDIR)/build.sh kernel_only
	@echo "  [✓] Ядро собрано"

# ── Только rootfs ─────────────────────────────────────────────
rootfs:
	@echo "  [→] Создание rootfs..."
	@bash $(CURDIR)/build.sh rootfs_only
	@echo "  [✓] rootfs готов"

# ── Только ISO ────────────────────────────────────────────────
iso:
	@echo "  [→] Сборка ISO-образа..."
	@bash $(CURDIR)/build.sh iso_only
	@echo "  [✓] ISO создан"

# ── Только тема ───────────────────────────────────────────────
theme-only:
	@echo "  [→] Применение темы..."
	@cp -r $(THEME)/* $(BUILD_DIR)/rootfs/root/theme/ 2>/dev/null || true
	@chroot $(BUILD_DIR)/rootfs /bin/bash /root/theme/apply_theme.sh
	@echo "  [✓] Тема применена"

# ── Только языки программирования ────────────────────────────
lang-only:
	@echo "  [→] Установка языков..."
	@cp $(SCRIPTS)/install_langs.sh $(BUILD_DIR)/rootfs/install_langs.sh
	@chmod +x $(BUILD_DIR)/rootfs/install_langs.sh
	@chroot $(BUILD_DIR)/rootfs /bin/bash /install_langs.sh
	@rm -f $(BUILD_DIR)/rootfs/install_langs.sh
	@echo "  [✓] Языки установлены"

# ── Только LKRG ───────────────────────────────────────────────
lkrg-only:
	@echo "  [→] Сборка LKRG..."
	@cp $(SCRIPTS)/install_lkrg.sh $(BUILD_DIR)/rootfs/install_lkrg.sh
	@chmod +x $(BUILD_DIR)/rootfs/install_lkrg.sh
	@chroot $(BUILD_DIR)/rootfs /bin/bash /install_lkrg.sh
	@rm -f $(BUILD_DIR)/rootfs/install_lkrg.sh
	@echo "  [✓] LKRG установлен"

# ── Инициализация strata пакетных менеджеров ─────────────────
strata-init:
	@echo "  [→] Инициализация strata..."
	@mkdir -p /var/lib/blacklinux/strata
	@bash $(SCRIPTS)/multipm.sh strata
	@echo "  [✓] Strata инициализированы"

# ── Запуск графического установщика ──────────────────────────
install-to-disk:
	@echo "  [→] Запуск установщика..."
	@bash $(SCRIPTS)/installer.sh

# ── Записать ISO на флешку ────────────────────────────────────
flash:
	@ISO=$$(ls -t $(OUTPUT_DIR)/*.iso 2>/dev/null | head -1); \
	[ -n "$$ISO" ] || { echo "  [!] ISO не найден в $(OUTPUT_DIR)"; exit 1; }; \
	DEVICE=$$(zenity --entry --title="Запись ISO" \
	    --text="Введите устройство (например /dev/sdb):" 2>/dev/null || \
	    read -p "Устройство (напр. /dev/sdb): " D && echo $$D); \
	[ -n "$$DEVICE" ] || exit 1; \
	echo "  [→] Запись $$ISO на $$DEVICE ..."; \
	dd if="$$ISO" of="$$DEVICE" bs=4M status=progress oflag=sync && \
	echo "  [✓] Запись завершена"

# ── Очистка ───────────────────────────────────────────────────
clean:
	@echo "  [→] Очистка..."
	@umount -lf $(BUILD_DIR)/rootfs/dev  2>/dev/null || true
	@umount -lf $(BUILD_DIR)/rootfs/proc 2>/dev/null || true
	@umount -lf $(BUILD_DIR)/rootfs/sys  2>/dev/null || true
	@rm -rf $(BUILD_DIR)/rootfs $(BUILD_DIR)/iso
	@echo "  [✓] Очищено (ядро и ISO сохранены)"

# ── Полная очистка (включая ядро и ISO) ──────────────────────
distclean: clean
	@rm -rf $(BUILD_DIR) $(OUTPUT_DIR)
	@echo "  [✓] Полная очистка завершена"

# ── Информация об ISO ─────────────────────────────────────────
info:
	@echo ""
	@echo "  ── Black Linux Build Info ──"
	@ls -lh $(OUTPUT_DIR)/*.iso 2>/dev/null || echo "  ISO не найден"
	@echo ""
	@[ -f $(BUILD_DIR)/hw_profile.env ] && \
	    { echo "  ── Профиль оборудования ──"; \
	      cat $(BUILD_DIR)/hw_profile.env; } || true
	@echo ""

# ── Помощь ───────────────────────────────────────────────────
help:
	@echo ""
	@echo "  ╔═══════════════════════════════════════════════╗"
	@echo "  ║         BLACK LINUX — Build System            ║"
	@echo "  ╠═══════════════════════════════════════════════╣"
	@echo "  ║  sudo make              — Полная сборка       ║"
	@echo "  ║  sudo make kernel       — Только ядро         ║"
	@echo "  ║  sudo make rootfs       — Только rootfs       ║"
	@echo "  ║  sudo make iso          — Только ISO          ║"
	@echo "  ║  sudo make theme-only   — Только тема         ║"
	@echo "  ║  sudo make lang-only    — Только языки        ║"
	@echo "  ║  sudo make lkrg-only    — Только LKRG         ║"
	@echo "  ║  sudo make strata-init  — Инит. PM strata     ║"
	@echo "  ║  sudo make flash        — Записать на флешку  ║"
	@echo "  ║  sudo make install-to-disk — Установить       ║"
	@echo "  ║  sudo make info         — Информация          ║"
	@echo "  ║  sudo make clean        — Очистка сборки      ║"
	@echo "  ║  sudo make distclean    — Полная очистка      ║"
	@echo "  ╚═══════════════════════════════════════════════╝"
	@echo ""
