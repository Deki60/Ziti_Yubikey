#!/bin/bash
#
# install_yubico_piv_tool.sh
#
# Ce script installe yubico-piv-tool sur une plateforme Debian (ou dérivés),
# en se basant sur les instructions officielles de compilation pour POSIX.
#
# Prérequis nécessaires (noms Debian) :
#   - cmake
#   - libtool
#   - libssl-dev
#   - pkg-config
#   - check
#   - libpcsclite-dev
#   - gengetopt (version 2.22.6 ou ultérieure)
#   - help2man
#   - zlib1g-dev
#   - g++
#
# Ce script réalise les étapes suivantes :
#   1. Vérifie que l'utilisateur est root.
#   2. Met à jour la liste des paquets et installe les dépendances requises.
#   3. Clone le dépôt Git de yubico-piv-tool (si nécessaire).
#   4. Crée un répertoire build, exécute cmake, compile et installe.
#   5. Met à jour le cache des bibliothèques avec ldconfig.
#
# Usage :
#   sudo ./install_yubico_piv_tool.sh
#

set -e

# 1. Vérifier que l'utilisateur est root
if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root (ou avec sudo)."
    exit 1
fi

# 2. Mettre à jour les paquets et installer les dépendances requises
echo "Mise à jour de la liste des paquets et installation des dépendances..."
apt update
apt install -y cmake libtool libssl-dev pkg-config check libpcsclite-dev gengetopt help2man zlib1g-dev g++

# 3. Cloner le dépôt Git de yubico-piv-tool (si non présent)
if [ ! -d "yubico-piv-tool" ]; then
    echo "Clonage du dépôt Git de yubico-piv-tool..."
    git clone https://github.com/Yubico/yubico-piv-tool.git
else
    echo "Le répertoire yubico-piv-tool existe déjà, utilisation du dépôt local."
fi

# 4. Compiler et installer
echo "Compilation et installation de yubico-piv-tool..."
cd yubico-piv-tool
mkdir -p build && cd build
cmake ..
make -j"$(nproc)"
make install

# 5. Mettre à jour le cache des bibliothèques partagées
echo "Mise à jour du cache des bibliothèques partagées..."
ldconfig

echo "Installation de yubico-piv-tool terminée avec succès."
