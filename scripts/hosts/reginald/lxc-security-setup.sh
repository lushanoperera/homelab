#!/bin/bash
#
# Script per installare e configurare unattended-upgrades su container LXC Debian/Ubuntu
# Questo script configura gli aggiornamenti automatici di sicurezza su tutti i container
# Compatibile con Debian e Ubuntu LXC
#

# Colori per una migliore leggibilità
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funzione per il logging
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Funzione per verificare errori
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERRORE: $1${NC}"
        exit 1
    fi
}

# Funzione per verificare se un container è in esecuzione
is_container_running() {
    local vmid=$1
    local status=$(pct status $vmid 2>/dev/null)
    
    if [[ "$status" == "status: running" ]]; then
        return 0  # Container in esecuzione
    else
        return 1  # Container non in esecuzione
    fi
}

# Funzione per ottenere l'OS del container
get_container_os() {
    local vmid=$1
    local os_type=""
    
    # Verifica se è possibile eseguire il comando nel container
    if pct exec $vmid -- test -f /etc/os-release; then
        # Determina il tipo di OS basato su /etc/os-release
        os_type=$(pct exec $vmid -- bash -c 'source /etc/os-release && echo $ID')
    else
        # Fallback per i container senza /etc/os-release
        if pct exec $vmid -- test -f /etc/debian_version; then
            os_type="debian"
        elif pct exec $vmid -- test -f /etc/lsb-release; then
            os_type="ubuntu"
        else
            os_type="unknown"
        fi
    fi
    
    echo $os_type
}

# Funzione per installare unattended-upgrades su container Debian/Ubuntu
install_unattended_upgrades() {
    local vmid=$1
    local os_type=$2
    
    log "${GREEN}Installazione unattended-upgrades sul container $vmid (OS: $os_type)...${NC}"
    
    # Installa i pacchetti necessari
    pct exec $vmid -- apt-get update
    check_error "Impossibile aggiornare l'indice dei pacchetti sul container $vmid"
    
    pct exec $vmid -- apt-get install -y unattended-upgrades apt-listchanges apticron
    check_error "Impossibile installare i pacchetti sul container $vmid"
    
    # Configura 20auto-upgrades
    log "Configurazione auto-upgrades..."
    pct exec $vmid -- bash -c 'cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Verbose "2";
EOF'
    check_error "Impossibile configurare 20auto-upgrades sul container $vmid"
    
    # Configura 50unattended-upgrades
    log "Configurazione unattended-upgrades..."
    
    # La configurazione varia leggermente tra Debian e Ubuntu
    if [[ "$os_type" == "debian" ]]; then
        pct exec $vmid -- bash -c 'cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=\${distro_codename},label=Debian-Security";
    "origin=Debian,codename=\${distro_codename}-security";
    "origin=Debian,codename=\${distro_codename},label=Debian";
    "origin=Debian,codename=\${distro_codename}-updates";
};

// Configurazione di base per gli aggiornamenti automatici
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
Unattended-Upgrade::OnlyOnACPower "false";
Unattended-Upgrade::Skip-Updates-On-Metered-Connections "false";

// Gestione degli errori
Unattended-Upgrade::OnlyOnACPower "false";
Unattended-Upgrade::Skip-Updates-On-Metered-Connections "false";
Unattended-Upgrade::Mail "";

// Blacklistare pacchetti specifici (non aggiornare questi pacchetti)
Unattended-Upgrade::Package-Blacklist {
//    "libc6";
//    "php*";
//    "mysql*";
};
EOF'
    else  # Ubuntu
        pct exec $vmid -- bash -c 'cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
    "${distro_id}:${distro_codename}-updates";
};

// Configurazione di base per gli aggiornamenti automatici
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
Unattended-Upgrade::OnlyOnACPower "false";
Unattended-Upgrade::Skip-Updates-On-Metered-Connections "false";

// Gestione degli errori
Unattended-Upgrade::OnlyOnACPower "false";
Unattended-Upgrade::Skip-Updates-On-Metered-Connections "false";
Unattended-Upgrade::Mail "";

// Blacklistare pacchetti specifici (non aggiornare questi pacchetti)
Unattended-Upgrade::Package-Blacklist {
//    "libc6";
//    "php*";
//    "mysql*";
};
EOF'
    fi
    check_error "Impossibile configurare 50unattended-upgrades sul container $vmid"
    
    # Attiva il servizio
    pct exec $vmid -- systemctl enable unattended-upgrades
    check_error "Impossibile attivare il servizio unattended-upgrades sul container $vmid"
    
    pct exec $vmid -- systemctl restart unattended-upgrades
    check_error "Impossibile riavviare il servizio unattended-upgrades sul container $vmid"
    
    # Verifica la configurazione
    log "Verifica della configurazione..."
    pct exec $vmid -- unattended-upgrades --dry-run --debug
    
    log "${GREEN}Configurazione completata con successo sul container $vmid${NC}"
}

# Funzione principale
main() {
    log "${BLUE}====== Installazione unattended-upgrades su container LXC ======${NC}"
    
    # Ottieni la lista dei container
    containers=$(pct list | tail -n +2 | awk '{print $1}')
    
    if [ -z "$containers" ]; then
        log "${YELLOW}Nessun container trovato${NC}"
        exit 0
    fi
    
    # Itera attraverso i container
    for vmid in $containers; do
        # Verifica se il container è in esecuzione
        if is_container_running $vmid; then
            # Ottieni il tipo di OS
            os_type=$(get_container_os $vmid)
            
            # Verifica se è un OS supportato
            if [[ "$os_type" == "debian" || "$os_type" == "ubuntu" ]]; then
                # Verifica se unattended-upgrades è già installato
                if pct exec $vmid -- dpkg -l | grep -q unattended-upgrades; then
                    log "${YELLOW}unattended-upgrades è già installato sul container $vmid (OS: $os_type). Aggiornamento configurazione...${NC}"
                    install_unattended_upgrades $vmid $os_type
                else
                    log "${GREEN}Installazione unattended-upgrades sul container $vmid (OS: $os_type)${NC}"
                    install_unattended_upgrades $vmid $os_type
                fi
            else
                log "${YELLOW}Container $vmid: Sistema operativo non supportato ($os_type). Saltato.${NC}"
            fi
        else
            log "${YELLOW}Container $vmid non in esecuzione. Saltato.${NC}"
        fi
    done
    
    log "${GREEN}====== Installazione completata ======${NC}"
}

# Esegui il programma principale
main

exit 0
