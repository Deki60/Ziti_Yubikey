# Ziti_Yubikey


This script performs the enrollment of an OpenZiti identity using a YubiKey as HSM.
It checks that the system is Debian, that the required tools are installed,
and offers to install the missing packages (ykman, pkcs11-tool, yubico-piv-tool, opensc).

The reference documentation for using a YubiKey with OpenZiti is available here:

https://openziti.io/docs/guides/hsm/yubikey/

https://openziti.discourse.group/t/yubikey-fido/3894/3

https://openziti.discourse.group/t/zdew-yubikey-support/2790/4

Usage (run as root):

sudo ./yubikey-enroll.sh <base_identity_name>

Example:

sudo ./yubikey-enroll.sh myZitiIdentity
