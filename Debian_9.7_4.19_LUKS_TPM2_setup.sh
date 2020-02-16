#!/bin/sh

cat >> /etc/apt/sources.list <<EOF
deb http://ftp.de.debian.org/debian/ stretch main
deb-src http://ftp.de.debian.org/debian/ stretch main

deb http://security.debian.org/debian-security stretch/updates main
deb-src http://security.debian.org/debian-security stretch/updates main

deb http://ftp.de.debian.org/debian/ stretch-updates main
deb-src http://ftp.de.debian.org/debian/ stretch-updates main

deb http://ftp.de.debian.org/debian/ stretch-backports main
deb http://ftp.de.debian.org/debian/ sid main
EOF

cat >> /etc/initramfs-tools/modules <<EOF
tpm_crb
tpm_tis
tpm_tis_core
tpm
rng_core
EOF

cat > /usr/share/initramfs-tools/hooks/tpm2 <<EOF
#!/bin/sh -e
if [ "\$1" = "prereqs" ]; then exit 0; fi
. /usr/share/initramfs-tools/hook-functions
copy_exec /usr/bin/tpm2_unseal
copy_exec /usr/lib/x86_64-linux-gnu/libtss2-tcti-device.so
EOF
chmod +x /usr/share/initramfs-tools/hooks/tpm2

cat > /usr/local/bin/passphrase-from-tpm <<EOF
#!/bin/sh
echo "Unlocking via TPM" >&2
export TPM2TOOLS_TCTI_NAME=device
export TPM2TOOLS_DEVICE_FILE=/dev/tpmrm0
exec 6>&2 2>/dev/null
LUKSPASS=\`/usr/bin/tpm2_unseal -Q -H 0x81010003 -L sha1:"0,1,2,3,7"\`
if [ \$? -eq 0 ]
then
        printf \${LUKSPASS}
else
        exec 2>&6
        /lib/cryptsetup/askpass "Unlocking the disk fallback \$CRYPTTAB_SOURCE (\$CRYPTTAB_NAME)\nEnter passphrase: "
fi
EOF
chmod +x /usr/local/bin/passphrase-from-tpm

cat > /usr/local/bin/passphrase-tpm-seal <<EOF
#!/bin/sh

if [ -z \${1} ]
then
	echo "Usage: \${0} [LUKS passphrase]"
	exit 1
fi

export TPM2TOOLS_TCTI_NAME=device
export TPM2TOOLS_DEVICE_FILE=/dev/tpmrm0
rm *.data
tpm2_takeownership -c
tpm2_createprimary -Q -H e -g sha256 -G ecc -C primary.ctx.data
tpm2_pcrlist -Q -L sha1:"0,1,2,3,7" -o pcr.data
tpm2_createpolicy -Q -P -L sha1:"0,1,2,3,7" -F pcr.data -f policy.data
tpm2_create -Q -g sha256 -G keyedhash -u key.pub.data -r key.priv.data -I- -c primary.ctx.data -L policy.data -A 'sign|fixedtpm|fixedparent|sensitivedataorigin' <<< \${1}
tpm2_load -Q -c primary.ctx.data  -u key.pub.data  -r key.priv.data -n key.name.data -C key.ctx.data
tpm2_evictcontrol -Q -A o -c key.ctx.data -S 0x81010003
rm *.data
EOF
chmod +x /usr/local/bin/passphrase-tpm-seal

