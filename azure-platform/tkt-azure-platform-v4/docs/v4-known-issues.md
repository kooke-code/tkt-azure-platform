# V4 Known Issues and Limitations

**Version:** 4.0  
**Date:** 2026-02-12  

---

## Known Issues

### 1. Registration Token Expiration (24 hours)
**Workaround:** Re-run Phase 3 or manually generate new token via Azure CLI.

### 2. FSLogix Requires Reboot
**Workaround:** Reboot session hosts after deployment completes.

### 3. Conditional Access in Report-Only Mode
**Workaround:** Manually enable policy in Entra ID portal after testing.

### 4. Graph API Propagation Delay (up to 5 min)
**Workaround:** Wait 5 minutes after `az login` before running deployment.

### 5. License Assignment Delay (up to 15 min)
**Workaround:** Wait before running validation; licenses will appear.

---

## Limitations

| Limitation | Reason | Workaround |
|------------|--------|------------|
| Single region only | Cost optimization | Duplicate RG for multi-region |
| No Azure Firewall | €125/month savings | Use Defender for Endpoint |
| No hybrid AD join | No on-prem AD in scope | Add if needed |
| No SAP pre-installed | License varies by customer | Manual install |
| No Azure Backup | €60/month savings | Add if needed |

---

## Manual Steps Required

1. **Enable Conditional Access policy** (after testing)
2. **Install SAP GUI** on session hosts
3. **Distribute credentials** to users via secure channel
4. **Reboot session hosts** after first deployment

---

## Optional Features (Run After Deployment)

| Feature | Script | Notes |
|---------|--------|-------|
| VM Schedule (07:00-18:00 Brussels) | `setup-vm-schedule.sh` | Saves ~€95/month |
| Activity Logging | `setup-session-logging.sh` | Logs to Log Analytics |
| Video Recording | `setup-session-logging.sh --enable-teramind` | Requires Teramind account (~€25/user/month) |

---

## Support

For issues not covered here, check deployment logs in `/tmp/avd-deployment-*.log`
