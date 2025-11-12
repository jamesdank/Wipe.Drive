⚠️ <font color="red"><b>DANGER: This permanently destroys data. Run from a live USB or another machine.
Do NOT run on a mounted device. Double-check the target drive.</b></font>

🧹 Wipe Drive — Secure Disk Erasure Utility</br>

<b>Description:</b></br>
wipe-drive.sh is a Linux-based interactive utility for securely erasing storage devices before disposal, resale, or OS reinstallation.
It automatically detects whether a target disk is a traditional hard drive (HDD) or a solid-state drive (SSD) and applies the appropriate secure-wipe method for each technology type.

<b>Features:</b></br>
🔍 Automatic drive type detection — distinguishes HDDs (rotational) from SSDs (non-rotational).</br>
🧱 Multiple security levels for HDDs via shred:</br>

<b>Security Level	Command	Passes</b></br>
Personal wipe	shred -vzn 1	1	Fast and secure for reinstalls</br>
Business / resale	shred -vzn 3	3	DoD short form</br>
Government-grade	shred -vzn 7	7	DoD 5220.22-M compliant</br>
Paranoid / forensic	shred -vzn 35	35	Gutmann method</br>

⚡ <b>SSD-specific secure erase methods:</b></br>
blkdiscard (safe, fast, TRIM-based wipe)</br>
nvme format -s1 for NVMe drives</br>
hdparm --security-erase for SATA drives</br>

🛡️ Failsafe prompts and confirmations prevent accidental data loss.</br>
🧠 Smart mount checks ensure no mounted partitions are wiped.</br>
💾 Sync and verification steps to ensure completion and data integrity.</br>

<b>Usage:</b></br>
chmod +x wipe-drive.sh</br>
sudo ./wipe-drive.sh</br>

<b>Requirements:</b></br>
Linux environment with coreutils, util-linux, and (optionally) nvme-cli and hdparm.</br>

Must be run with sudo privileges.</br>

<b>Purpose:</b></br>
Ideal for system administrators, refurbishers, and privacy-minded users who want a safe, verifiable, and standards-compliant disk wipe before reusing or decommissioning hardware.
