# Script PowerShell pour enrôler une identité OpenZiti avec une YubiKey
# Fonctionne sous Windows

# Vérification de l'exécution en mode administrateur
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Ce script doit être exécuté en mode administrateur." -ForegroundColor Red
    exit 1
}

# Vérification de la présence des outils requis
$tools = @(
    @{Name="ykman"; InstallLink="https://developers.yubico.com/yubikey-manager/"},
    @{Name="pkcs11-tool"; InstallLink="https://github.com/OpenSC/OpenSC/releases"},
    @{Name="yubico-piv-tool"; InstallLink="https://developers.yubico.com/yubico-piv-tool/"},
    @{Name="ziti"; InstallLink="https://openziti.io/"}
)

foreach ($tool in $tools) {
    if (-not (Get-Command $tool.Name -ErrorAction SilentlyContinue)) {
        Write-Host "L'outil '$($tool.Name)' n'est pas installé. Veuillez l'installer ici : $($tool.InstallLink)" -ForegroundColor Yellow
        exit 1
    }
}

# Demande des informations utilisateur
function Read-UserInput($message, $default) {
    $inputValue = Read-Host "$message [$default]"
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        return $default
    }
    return $inputValue
}

$ZITI_CTRL = Read-UserInput "Entrez le nom du contrôleur Ziti (adresse ou DNS)" "local-edge-controller"
$ZITI_PORT = Read-UserInput "Entrez le port du contrôleur" "1280"
$ZITI_CTRL_CERT = Read-UserInput "Entrez le chemin du certificat du contrôleur" "C:\path\to\controller.cert"
$ZITI_USER = Read-UserInput "Entrez le nom d'utilisateur Ziti" "myUserName"
$ZITI_PWD = Read-Host "Entrez le mot de passe Ziti" -AsSecureString
$HSM_NAME = Read-UserInput "Entrez le nom de la configuration HSM" "yubikey_demo"
$PKCS11_MODULE = Read-UserInput "Entrez le chemin complet vers libykcs11.dll" "C:\Program Files\Yubico\libykcs11.dll"
$HSM_ID1 = Read-UserInput "Entrez HSM_ID1 (ID pour la clé RSA)" "01"
$HSM_ID2 = Read-UserInput "Entrez HSM_ID2 (ID pour la clé EC)" "03"
$HSM_SOPIN = Read-UserInput "Entrez le SOPIN (Clé de gestion) de la YubiKey" "010203040506070801020304050607080102030405060708"
$HSM_PIN = Read-UserInput "Entrez le PIN de la YubiKey" "123456"
$HSM_DEST = Read-UserInput "Entrez le chemin où seront stockés les fichiers de configuration HSM" "C:\ZitiHSM\$HSM_NAME"

# Vérification de la présence d'une YubiKey
Write-Host "Recherche de YubiKey..."
if (-not (ykman list | Select-String "YubiKey")) {
    Write-Host "Aucune YubiKey détectée. Assurez-vous qu'elle est branchée et initialisée." -ForegroundColor Red
    exit 1
}
Write-Host "YubiKey détectée !" -ForegroundColor Green

# Connexion à OpenZiti
Write-Host "Connexion au contrôleur Ziti..."
$ZITI_PWD_PLAIN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ZITI_PWD))
ziti edge login "$ZITI_CTRL`:$ZITI_PORT" -u "$ZITI_USER" -p "$ZITI_PWD_PLAIN"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Échec de la connexion au contrôleur Ziti." -ForegroundColor Red
    exit 1
}

# Création des identités OpenZiti
$RSA_ID = "$HSM_NAME$HSM_ID1`_rsa"
$EC_ID = "$HSM_NAME$HSM_ID2`_ec"
ziti edge create identity $RSA_ID -o "$HSM_DEST\$RSA_ID.jwt"
ziti edge create identity $EC_ID -o "$HSM_DEST\$EC_ID.jwt"

# Initialisation de la YubiKey
Write-Host "Initialisation du token sur la YubiKey..."
pkcs11-tool --module "$PKCS11_MODULE" --init-token --label "ziti-test-token" --so-pin "$HSM_SOPIN"

# Création des clés sur la YubiKey
Write-Host "Création de la clé RSA..."
pkcs11-tool --module "$PKCS11_MODULE" -k --key-type rsa:2048 --usage-sign --usage-decrypt --login --id "$HSM_ID1" --login-type so --so-pin "$HSM_SOPIN" --label defaultkey

Write-Host "Création de la clé EC..."
pkcs11-tool --module "$PKCS11_MODULE" -k --key-type EC:prime256v1 --usage-sign --usage-decrypt --login --id "$HSM_ID2" --login-type so --so-pin "$HSM_SOPIN" --label defaultkey

# Enrôlement des identités
Write-Host "Enrôlement des identités..."
ziti edge enroll "$HSM_DEST\$RSA_ID.jwt"
ziti edge enroll "$HSM_DEST\$EC_ID.jwt"

Write-Host "Enrôlement et configuration terminés avec succès." -ForegroundColor Green
