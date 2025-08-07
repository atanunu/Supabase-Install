# 🔄 Comprehensive Disaster Recovery Procedures
# Emergency Response and Recovery Playbook for Supabase

## 🚨 **Emergency Response Matrix**

### **Severity Levels**
- **🔴 CRITICAL**: Complete system failure, data loss risk
- **🟡 HIGH**: Service degraded, backup issues
- **🟢 MEDIUM**: Minor issues, preventive maintenance

---

## 📋 **Pre-Recovery Checklist**

### **Before Starting Recovery**
1. ✅ **Assess the situation**
   - Identify the scope of the problem
   - Determine data loss extent
   - Estimate recovery time objective (RTO)
   - Identify recovery point objective (RPO)

2. ✅ **Notify stakeholders**
   - Send initial incident notification
   - Activate incident response team
   - Set up communication channels

3. ✅ **Secure the environment**
   - Stop any ongoing operations
   - Preserve current state for analysis
   - Take system snapshots if possible

---

## 🔄 **Recovery Procedures**

### **1. Complete Database Recovery (CRITICAL)**

#### **Scenario**: PostgreSQL database corruption or complete loss

```bash
# 1. Stop all Supabase services
docker compose down

# 2. Backup current state (if accessible)
docker run --rm -v postgres_data:/data alpine tar czf /backup/emergency_backup_$(date +%Y%m%d_%H%M%S).tar.gz -C /data .

# 3. Restore from latest backup
cd backup_recovery
./scripts/restore_database.sh latest

# 4. Verify restoration
./scripts/backup_validator.sh test-postgres /backups/latest.custom

# 5. Start services
docker compose up -d

# 6. Verify system health
curl -f http://localhost:8000/health
```

#### **Point-in-Time Recovery (PITR)**

```bash
# Restore to specific time
./scripts/wal_manager.sh restore "2024-01-15 14:30:00" time

# Restore to specific transaction ID
./scripts/wal_manager.sh restore "12345678" xid

# Restore to named restore point
./scripts/wal_manager.sh restore "before_migration" name
```

### **2. Storage Recovery (HIGH)**

#### **Scenario**: File storage corruption or loss

```bash
# 1. Stop storage services
docker compose stop storage

# 2. Restore storage from backup
./scripts/storage_backup.sh restore storage_backup_20240115_020000

# 3. Verify storage integrity
./scripts/backup_validator.sh test-storage /storage_backups/latest.tar.gz

# 4. Restart storage services
docker compose start storage

# 5. Test file upload/download
curl -X POST -F "file=@test.txt" http://localhost:8000/storage/v1/upload
```

### **3. Cross-Region Failover (CRITICAL)**

#### **Scenario**: Primary region failure

```bash
# 1. Activate cross-region resources
export AWS_REGION=us-west-2
export AWS_S3_BUCKET=your-supabase-backups-west

# 2. Download latest backups from cross-region
aws s3 sync s3://your-supabase-backups-west/postgres/full-backups/ /backups/

# 3. Restore database in new region
./scripts/backup_manager.sh restore

# 4. Update DNS/load balancer to new region
# (Manual step - update your DNS provider)

# 5. Verify all services
./scripts/health_check.sh full
```

### **4. Partial Data Recovery (MEDIUM)**

#### **Scenario**: Specific table or data corruption

```bash
# 1. Create restore point before recovery
./scripts/wal_manager.sh restore-point "before_partial_recovery"

# 2. Export specific table from backup
pg_restore -h localhost -U supabase -d supabase --table=specific_table /backups/latest.custom

# 3. Compare and merge data
psql -h localhost -U supabase -d supabase -c "
  -- Custom SQL for data comparison and merge
  SELECT * FROM specific_table_backup EXCEPT SELECT * FROM specific_table;
"

# 4. Verify data integrity
./scripts/data_integrity_check.sh specific_table
```

---

## ⏱️ **Recovery Time Objectives (RTO)**

| **Scenario** | **Target RTO** | **Maximum RTO** |
|--------------|----------------|-----------------|
| Database corruption | 30 minutes | 2 hours |
| Storage failure | 15 minutes | 1 hour |
| Cross-region failover | 1 hour | 4 hours |
| Partial data recovery | 10 minutes | 30 minutes |

## 📊 **Recovery Point Objectives (RPO)**

| **Data Type** | **Target RPO** | **Maximum RPO** |
|---------------|----------------|-----------------|
| Database transactions | 5 minutes | 15 minutes |
| File uploads | 1 hour | 4 hours |
| Configuration changes | Immediate | 5 minutes |

---

## 🔍 **Post-Recovery Procedures**

### **1. Verification Checklist**
```bash
# Database connectivity
psql -h localhost -U supabase -d supabase -c "SELECT version();"

# Authentication system
curl -X POST http://localhost:8000/auth/v1/token \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpass"}'

# Storage system
curl -X GET http://localhost:8000/storage/v1/buckets

# Real-time subscriptions
# (Test through your application)

# REST API
curl -X GET http://localhost:8000/rest/v1/users \
  -H "Authorization: Bearer your-anon-key"
```

### **2. Data Integrity Verification**
```bash
# Run comprehensive validation
./scripts/backup_validator.sh validate

# Check row counts
psql -h localhost -U supabase -d supabase -c "
  SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes
  FROM pg_stat_user_tables 
  ORDER BY schemaname, tablename;
"

# Verify critical business data
# (Run your specific data validation queries)
```

### **3. Performance Baseline**
```bash
# Database performance
psql -h localhost -U supabase -d supabase -c "
  SELECT query, calls, total_time, mean_time 
  FROM pg_stat_statements 
  ORDER BY mean_time DESC LIMIT 10;
"

# System resources
docker stats --no-stream

# Response times
curl -w "@curl-format.txt" -o /dev/null -s http://localhost:8000/health
```

---

## 📞 **Emergency Contacts**

### **Internal Team**
- **Primary DBA**: +1-xxx-xxx-xxxx
- **DevOps Lead**: +1-xxx-xxx-xxxx  
- **Security Officer**: +1-xxx-xxx-xxxx

### **External Vendors**
- **AWS Support**: 1-800-xxx-xxxx
- **Database Consultant**: +1-xxx-xxx-xxxx
- **Security Firm**: +1-xxx-xxx-xxxx

### **Communication Channels**
- **Slack**: #incident-response
- **Email**: incidents@yourdomain.com
- **Status Page**: status.yourdomain.com

---

## 📚 **Common Recovery Scenarios**

### **Scenario 1: "Accidental Data Deletion"**
**Symptoms**: Missing records, user complaints
**Recovery**: PITR to just before deletion time
**RTO**: 15 minutes | **RPO**: 5 minutes

### **Scenario 2: "Failed Migration"**
**Symptoms**: Application errors, schema issues
**Recovery**: Restore from pre-migration backup
**RTO**: 30 minutes | **RPO**: Immediate

### **Scenario 3: "Corruption After Update"**
**Symptoms**: Database errors, slow queries
**Recovery**: Full database restore from clean backup
**RTO**: 1 hour | **RPO**: 15 minutes

### **Scenario 4: "Region-Wide Outage"**
**Symptoms**: Complete service unavailability
**Recovery**: Cross-region failover activation
**RTO**: 2 hours | **RPO**: 1 hour

---

## 🛠️ **Recovery Tools Reference**

### **Backup Manager Commands**
```bash
# Full backup
./backup_manager.sh full

# List available backups
./backup_manager.sh list

# Restore specific backup
./backup_manager.sh restore backup_20240115_020000
```

### **WAL Manager Commands**
```bash
# Setup PITR
./wal_manager.sh setup

# Create restore point
./wal_manager.sh restore-point "migration_start"

# Monitor WAL archiving
./wal_manager.sh monitor
```

### **Validation Commands**
```bash
# Test all backups
./backup_validator.sh validate

# Test specific backup
./backup_validator.sh test-postgres /backups/specific.custom
```

---

## 📋 **Recovery Logging Template**

```
INCIDENT ID: INC-YYYY-MMDD-XXXX
START TIME: YYYY-MM-DD HH:MM:SS UTC
SEVERITY: [CRITICAL/HIGH/MEDIUM]
AFFECTED SYSTEMS: [Database/Storage/Auth/API]

PROBLEM DESCRIPTION:
[Detailed description of the issue]

IMPACT ASSESSMENT:
- Users affected: [number/percentage]
- Data loss: [Yes/No - extent if yes]  
- Services down: [list of affected services]

RECOVERY ACTIONS TAKEN:
1. [Action 1 - Time: HH:MM]
2. [Action 2 - Time: HH:MM]
3. [Action 3 - Time: HH:MM]

RESOLUTION TIME: HH:MM
ACTUAL RTO: [time taken]
ACTUAL RPO: [data loss extent]

POST-MORTEM ITEMS:
- [ ] Root cause analysis
- [ ] Process improvements
- [ ] Documentation updates
- [ ] Team training needs
```

---

## 🔄 **Recovery Testing Schedule**

### **Monthly Tests**
- [ ] Backup restoration validation
- [ ] Storage recovery procedures
- [ ] PITR functionality test

### **Quarterly Tests**
- [ ] Full disaster recovery drill
- [ ] Cross-region failover test
- [ ] End-to-end recovery simulation

### **Annual Tests**
- [ ] Complete infrastructure recovery
- [ ] Multi-failure scenario testing
- [ ] Business continuity validation

---

**📞 Emergency Hotline: +1-xxx-xxx-xxxx**
**📧 Emergency Email: emergency@yourdomain.com**
**🔗 Status Page: https://status.yourdomain.com**

*Last Updated: 2024-01-15*
*Next Review: 2024-04-15*
