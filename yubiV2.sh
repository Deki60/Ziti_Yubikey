#!/bin/bash
#
# yubikey-enroll.sh
#
# Ce script réalise l’enrôlement d’une identité OpenZiti en utilisant une YubiKey comme HSM.
# Il vérifie que le système est Debian (doc Ziti Ubuntu/Debian), que les outils requis sont installés,
# et propose d'installer les paquets manquants (ykman, pkcs11-tool, yubico-piv-tool, opensc).
#
# La documentation de référence pour l’utilisation d’une YubiKey avec OpenZiti est disponible ici :
#   https://openziti.io/docs/guides/hsm/yubikey/
#   https://openziti.discourse.group/t/yubikey-fido/3894/3
#   https://openziti.discourse.group/t/zdew-yubikey-support/2790/4
#
# Usage (exécuté en tant que root) :
#   sudo ./yubikey-enroll.sh <nom_identité_base>
#
# Exemple :
#   sudo ./yubikey-enroll.sh monIdentiteZiti
#

set -e

# --- 0. Vérifications système préliminaires ---

# Vérifier que le système est Debian en utilisant /etc/os-release
if [ -f /etc/os-release ]; then
  # Charger le fichier pour avoir accès aux variables (ex: ID)
  . /etc/os-release
  if [ "$ID" != "debian" ]; then
    echo "Ce script fonctionne uniquement sur Debian (Bookworm)."
    read -p "Voulez-vous continuer malgré tout ? [y/N]: " answer
    if [[ ! "$answer" =~ ^[Yy] ]]; then
      exit 1
    fi
  fi
else
  echo "/etc/os-release n'existe pas. Impossible de vérifier la distribution."
  # Vérifier en complément l'existence de /etc/debian_version
  if [ ! -f /etc/debian_version ]; then
    echo "Ce script est conçu pour Debian ou ses dérivés (Ubuntu, etc.)."
    read -p "Voulez-vous continuer malgré tout ? [y/N]: " answer
    if [[ ! "$answer" =~ ^[Yy] ]]; then
      exit 1
    fi
  fi
fi

# Fonction pour vérifier la présence d'une commande et, si elle manque, demander l'installation
check_command() {
  local cmd="$1"
  local pkg="$2"  # le nom du paquet à installer
  if ! command -v "$cmd" &>/dev/null; then
    echo "L'outil '$cmd' n'est pas installé."
    read -p "Voulez-vous installer '$pkg' (via apt) ? [Y/n]: " choice
    if [[ "$choice" =~ ^[Yy] || -z "$choice" ]]; then
      sudo apt update
      sudo apt install -y "$pkg"
    else
      echo "Impossible de continuer sans '$cmd'."
      exit 1
    fi
  fi
}

# Vérifier les outils requis
check_command "ykman" "yubikey-manager"
check_command "pkcs11-tool" "opensc"
check_command "ziti" "ziti"         # On suppose que le paquet s'appelle 'ziti' ou qu'il est sur le PATH
# Vérifier également yubico-piv-tool (pour obtenir le module PKCS#11)
check_command "yubico-piv-tool" "yubico-piv-tool"

# Vérifier que le module libykcs11.so existe à un emplacement connu
# Par défaut, nous utiliserons le chemin de compilation suggéré dans la doc.
DEFAULT_HSM_ROOT="/usr/local/lib/"
DEFAULT_PKCS11_MODULE="${DEFAULT_HSM_ROOT}libykcs11.so"
if [ ! -f "$DEFAULT_PKCS11_MODULE" ]; then
  echo "Le module PKCS#11 (libykcs11.so) n'a pas été trouvé à l'emplacement par défaut :"
  echo "$DEFAULT_PKCS11_MODULE"
  read -p "Veuillez fournir le chemin complet vers libykcs11.so : " CUSTOM_PKCS11_MODULE
  if [ -z "$CUSTOM_PKCS11_MODULE" ] || [ ! -f "$CUSTOM_PKCS11_MODULE" ]; then
    echo "Module introuvable. Veuillez installer et compiler yubico-piv-tool correctement."
    exit 1
  else
    DEFAULT_PKCS11_MODULE="$CUSTOM_PKCS11_MODULE"
    # On suppose que HSM_ROOT est le dossier parent de libykcs11.so
    DEFAULT_HSM_ROOT=$(dirname "$(dirname "$CUSTOM_PKCS11_MODULE")")
  fi
fi

# --- 1. Vérification de la présence d'une YubiKey ---

echo "Recherche de YubiKey..."
if ! ykman list | grep "YubiKey"; then
  echo "Aucune YubiKey détectée. Assurez-vous que la YubiKey est branchée et réinitialisée aux paramètres d'usine."
  exit 1
fi
echo "YubiKey détectée !"

# --- 2. Demande interactive des variables d'environnement ---

echo "=== Configuration de la connexion Ziti et HSM ==="
# Lecture avec valeur par défaut
read_with_default() {
  local prompt="$1"
  local default_val="$2"
  read -p "$prompt [$default_val]: " input
  echo "${input:-$default_val}"
}

export ZITI_CTRL=$(read_with_default "Entrez le nom du contrôleur Ziti (adresse ou DNS, ex: local-edge-controller)" "local-edge-controller")
export ZITI_PORT=$(read_with_default "Entrez le port du controleur" "defaut 1280")
export ZITI_CTRL_CERT=$(read_with_default "Entrez le chemin complet vers le certificat du contrôleur" "/path/to/controller.cert")
export ZITI_USER=$(read_with_default "Entrez le nom d'utilisateur Ziti" "myUserName")
read -s -p "Entrez le mot de passe Ziti : " ZITI_PWD; echo
export HSM_NAME=$(read_with_default "Entrez le nom de la configuration HSM" "yubikey_demo")
export HSM_ROOT=$(read_with_default "Entrez le chemin racine pour yubico-piv-tool" "$DEFAULT_HSM_ROOT")
export PKCS11_MODULE=$(read_with_default "Entrez le chemin complet vers libykcs11.so" "$DEFAULT_PKCS11_MODULE")
export HSM_ID2=$(read_with_default "Entrez HSM_ID2 (ID pour la clé EC)" "03")
export HSM_SOPIN=$(read_with_default "Entrez le SOPIN (Clé de gestion) de la YubiKey" "010203040506070801020304050607080102030405060708")
export HSM_PIN=$(read_with_default "Entrez le PIN d'utilisation de la YubiKey" "123456")
export EC_ID="${HSM_NAME}${HSM_ID2}_ec"
export HSM_DEST=$(read_with_default "Entrez le chemin où seront stockés les fichiers de configuration HSM" "${HSM_ROOT}/${HSM_NAME}")
export HSM_LABEL=$(read_with_default "Entrez le label pour la YubiKey" "${HSM_NAME}-label")

echo "-------------------------------"
echo "ZITI_CTRL: $ZITI_CTRL"
echo "ZITI_PORT: $ZITI_PORT"
echo "ZITI_CTRL_CERT: $ZITI_CTRL_CERT"
echo "ZITI_USER: $ZITI_USER"
echo "HSM_NAME: $HSM_NAME"
echo "HSM_ROOT: $HSM_ROOT"
echo "PKCS11_MODULE: $PKCS11_MODULE"
echo "HSM_ID2: $HSM_ID2"
echo "HSM_SOPIN: $HSM_SOPIN"
echo "HSM_PIN: $HSM_PIN"
echo "EC_ID: $EC_ID"
echo "HSM_DEST: $HSM_DEST"
echo "HSM_LABEL: $HSM_LABEL"
echo "-------------------------------"
read -p "Confirmez ces informations et appuyez sur Entrée pour continuer..."

# --- 3. Préparation du répertoire HSM ---

echo "Création du répertoire HSM_DEST..."
mkdir -p "$HSM_DEST" || { echo "Erreur lors de la création de $HSM_DEST"; exit 1; }

cd "$HSM_ROOT" || exit 1
rm -rf "$HSM_NAME"
mkdir -p "$HSM_NAME"
cd "$HSM_NAME" || exit 1

# --- 4. Connexion au contrôleur Ziti et création des identités ---

echo "Connexion au contrôleur Ziti..."
ziti edge login "$ZITI_CTRL:$ZITI_PORT" -u "$ZITI_USER" -p "$ZITI_PWD"
if [ $? -ne 0 ]; then
  echo "Échec de la connexion au contrôleur Ziti."
  exit 1
fi

echo "Création de l'identité EC ($EC_ID)..."
ziti edge create identity "$EC_ID" -o "${HSM_DEST}/${EC_ID}.jwt"
if [ $? -ne 0 ]; then
  echo "Échec de la création de l'identité EC."
  exit 1
fi

# --- 5. Configuration de la YubiKey via pkcs11-tool (alias p) ---

p() { pkcs11-tool --module "$PKCS11_MODULE" "$@"; }

echo "Initialisation du token sur la YubiKey..."
p --init-token --label "ziti-test-token" --so-pin "$HSM_SOPIN"
if [ $? -ne 0 ]; then
  echo "Échec de l'initialisation du token sur la YubiKey."
  exit 1
fi

echo "Création de la clé EC sur la YubiKey..."
p -k --key-type EC:prime256v1 --usage-sign --usage-decrypt --login --id "$HSM_ID2" --login-type so --so-pin "$HSM_SOPIN" --label defaultkey
if [ $? -ne 0 ]; then
  echo "Échec de la création de la clé EC."
  exit 1
fi

# --- 6. Enrôlement des identités via ziti edge enroll ---

echo "Enrôlement de l'identité EC via ziti edge..."
ziti-edge-tunnel enroll "${HSM_DEST}/${EC_ID}.jwt"
if [ $? -ne 0 ]; then
  echo "Échec de l'enrôlement de l'identité EC."
  exit 1
fi

echo "Enrôlement et configuration terminés avec succès."
exit 0
