# 📋 Operations Runbooks for Supabase Self-Hosting
# Standard Operating Procedures (SOPs) for Common Tasks

## 🎯 **Quick Reference**

### **Emergency Contacts**
- **Primary Admin**: [Your Name] - [Phone] - [Email]
- **Secondary Admin**: [Backup Admin] - [Phone] - [Email]
- **AWS Support**: 1-800-xxx-xxxx (Enterprise Support)
- **Emergency Escalation**: [Manager] - [Phone]

### **Critical Commands**
```bash
# Emergency stop all services
docker compose down

# Emergency restart
docker compose up -d

# Check system health
./health_check.sh --full

# View real-time logs
docker compose logs -f

# Emergency backup
supabase-backup full
```

---

## 🚀 **Routine Operations**

### **1. Daily Health Check**
**Frequency**: Every morning at 9 AM
**Duration**: 5 minutes
**Responsibility**: Operations Team

```bash
#!/bin/bash
# Daily health check routine

echo "=== Daily Supabase Health Check - $(date) ==="

# 1. Check service status
echo "1. Checking service status..."
docker compose ps

# 2. Check resource usage
echo "2. Checking resource usage..."
docker stats --no-stream

# 3. Check database connections
echo "3. Checking database connections..."
psql -h localhost -U supabase -d supabase -c "
SELECT 
    count(*) as total_connections,
    count(*) FILTER (WHERE state = 'active') as active_connections,
    count(*) FILTER (WHERE state = 'idle') as idle_connections
FROM pg_stat_activity;
"

# 4. Check backup status
echo "4. Checking recent backups..."
ls -la /backups/ | head -5

# 5. Check disk space
echo "5. Checking disk space..."
df -h

# 6. Check recent errors
echo "6. Checking recent errors..."
docker compose logs --since 24h | grep -i error | tail -10

echo "=== Health Check Complete ==="
```

### **2. Weekly Maintenance**
**Frequency**: Every Sunday at 2 AM
**Duration**: 30 minutes
**Responsibility**: Operations Team

```bash
#!/bin/bash
# Weekly maintenance routine

echo "=== Weekly Supabase Maintenance - $(date) ==="

# 1. Update system packages
sudo apt update && sudo apt upgrade -y

# 2. Clean up Docker resources
docker system prune -f
docker volume prune -f

# 3. Rotate logs
sudo logrotate /etc/logrotate.conf

# 4. Vacuum database
psql -h localhost -U supabase -d supabase -c "VACUUM ANALYZE;"

# 5. Update container images (if needed)
docker compose pull

# 6. Verify backup integrity
supabase-validate

# 7. Generate weekly report
./generate_weekly_report.sh

echo "=== Weekly Maintenance Complete ==="
```

### **3. Monthly Security Review**
**Frequency**: First Monday of each month
**Duration**: 2 hours
**Responsibility**: Security + Operations Team

```bash
#!/bin/bash
# Monthly security review

echo "=== Monthly Security Review - $(date) ==="

# 1. Update SSL certificates (if needed)
./ubuntu_ssl_setup.sh --check

# 2. Review user accounts
psql -h localhost -U supabase -d supabase -c "
SELECT email, created_at, last_sign_in_at 
FROM auth.users 
ORDER BY created_at DESC LIMIT 20;
"

# 3. Check for security updates
sudo apt list --upgradable | grep -i security

# 4. Review firewall rules
sudo ufw status verbose

# 5. Scan for vulnerabilities
./security_scan.sh

# 6. Review access logs
sudo tail -100 /var/log/auth.log

# 7. Update security documentation
echo "Review and update security procedures"

echo "=== Security Review Complete ==="
```

---

## 🔧 **Troubleshooting Procedures**

### **1. Service Won't Start**
**Symptom**: Docker container fails to start
**Impact**: Service degradation or outage

**Steps**:
1. Check container status
   ```bash
   docker compose ps
   docker compose logs [service_name]
   ```

2. Check resource availability
   ```bash
   free -h
   df -h
   docker system df
   ```

3. Check port conflicts
   ```bash
   sudo netstat -tlnp | grep [port]
   ```

4. Restart specific service
   ```bash
   docker compose restart [service_name]
   ```

5. If still failing, check configuration
   ```bash
   docker compose config
   ```

6. Escalate if not resolved in 15 minutes

### **2. Database Connection Issues**
**Symptom**: Cannot connect to PostgreSQL
**Impact**: Complete application failure

**Steps**:
1. Check PostgreSQL container status
   ```bash
   docker compose logs postgres
   ```

2. Test connection
   ```bash
   psql -h localhost -U supabase -d supabase -c "SELECT 1;"
   ```

3. Check connection pool
   ```bash
   psql -h localhost -U supabase -d supabase -c "
   SELECT count(*) FROM pg_stat_activity;
   "
   ```

4. Restart PostgreSQL if needed
   ```bash
   docker compose restart postgres
   ```

5. Check for disk space issues
   ```bash
   df -h /var/lib/docker
   ```

6. If data corruption suspected, restore from backup
   ```bash
   supabase-backup restore latest
   ```

### **3. High CPU/Memory Usage**
**Symptom**: System performance degradation
**Impact**: Slow response times

**Steps**:
1. Identify resource-heavy containers
   ```bash
   docker stats
   ```

2. Check database query performance
   ```bash
   psql -h localhost -U supabase -d supabase -c "
   SELECT query, calls, total_time, mean_time 
   FROM pg_stat_statements 
   ORDER BY total_time DESC LIMIT 10;
   "
   ```

3. Check for memory leaks
   ```bash
   free -h
   top -p $(pgrep -d, docker)
   ```

4. Scale resources if needed
   ```bash
   docker compose up -d --scale rest=2
   ```

5. Consider upgrading instance size

### **4. Backup Failures**
**Symptom**: Backup process fails
**Impact**: Data protection risk

**Steps**:
1. Check backup logs
   ```bash
   tail -100 /var/log/backup_manager.log
   ```

2. Test manual backup
   ```bash
   supabase-backup full
   ```

3. Check S3 connectivity
   ```bash
   aws s3 ls s3://your-bucket/
   ```

4. Verify disk space
   ```bash
   df -h /backups
   ```

5. Check PostgreSQL connectivity
   ```bash
   pg_dump --help
   psql -h localhost -U supabase -c "\l"
   ```

6. If S3 issues, check AWS credentials

---

## 📊 **Performance Tuning**

### **1. Database Optimization**
**When**: Query response times > 500ms
**How**:

```bash
# Check slow queries
psql -h localhost -U supabase -d supabase -c "
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    (total_time/calls) as avg_time_ms
FROM pg_stat_statements 
WHERE calls > 100
ORDER BY mean_time DESC 
LIMIT 20;
"

# Check index usage
psql -h localhost -U supabase -d supabase -c "
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes 
ORDER BY idx_scan DESC;
"

# Analyze table statistics
psql -h localhost -U supabase -d supabase -c "ANALYZE;"
```

### **2. Container Resource Adjustment**
**When**: CPU/Memory consistently above 80%
**How**:

```yaml
# Edit docker-compose.yml
services:
  postgres:
    deploy:
      resources:
        limits:
          memory: 2G      # Increase from 1G
          cpus: '2.0'     # Increase from 1.0
        reservations:
          memory: 1G
          cpus: '1.0'
```

### **3. Connection Pool Tuning**
**When**: Connection pool exhaustion
**How**:

```bash
# Check current connections
psql -h localhost -U supabase -d supabase -c "
SELECT 
    count(*) as total,
    count(*) FILTER (WHERE state = 'active') as active,
    count(*) FILTER (WHERE state = 'idle') as idle
FROM pg_stat_activity;
"

# Adjust PostgreSQL settings
psql -h localhost -U supabase -d supabase -c "
ALTER SYSTEM SET max_connections = 300;  -- Increase from 200
ALTER SYSTEM SET shared_buffers = '512MB';  -- Increase from 256MB
SELECT pg_reload_conf();
"
```

---

## 🚨 **Incident Response**

### **Severity Levels**
- **🔴 P1 - Critical**: Complete outage, data loss
- **🟡 P2 - High**: Major functionality impaired
- **🟢 P3 - Medium**: Minor issues, workarounds available
- **🔵 P4 - Low**: Cosmetic issues, future improvements

### **P1 - Critical Incident Response**
**Response Time**: Immediate (< 5 minutes)

1. **Immediate Actions** (0-5 minutes):
   ```bash
   # Assess the situation
   ./health_check.sh --emergency
   
   # Check all services
   docker compose ps
   
   # Review recent logs
   docker compose logs --since 30m | grep -i error
   ```

2. **Communication** (5-10 minutes):
   - Send incident notification
   - Update status page
   - Notify stakeholders

3. **Mitigation** (10-30 minutes):
   ```bash
   # Try service restart
   docker compose restart
   
   # If fails, restore from backup
   supabase-backup restore latest
   
   # Implement workaround if possible
   ```

4. **Resolution** (30-60 minutes):
   - Identify root cause
   - Apply permanent fix
   - Verify resolution
   - Update documentation

---

## 📈 **Scaling Procedures**

### **1. Horizontal Scaling**
**When**: CPU > 80% for > 15 minutes

```bash
# Scale API services
docker compose up -d --scale rest=3 --scale realtime=2

# Update load balancer configuration
# (Manual step - update nginx upstream)

# Monitor performance improvement
watch docker stats
```

### **2. Vertical Scaling**
**When**: Memory > 90% consistently

```bash
# Stop services
docker compose down

# Update resource limits in docker-compose.yml
# Increase memory and CPU allocations

# Restart with new limits
docker compose up -d

# Verify new limits
docker stats
```

### **3. Database Scaling**
**When**: Database CPU > 85% or connections > 80% of max

```bash
# Option 1: Increase resources
# Edit PostgreSQL memory settings

# Option 2: Add read replica
# Configure streaming replication

# Option 3: Connection pooling
# Implement PgBouncer if not already done
```

---

## 📝 **Maintenance Windows**

### **Planned Maintenance Schedule**
- **Daily**: 2:00 AM - 2:30 AM UTC (Backups)
- **Weekly**: Sunday 1:00 AM - 3:00 AM UTC (Updates)
- **Monthly**: First Sunday 12:00 AM - 4:00 AM UTC (Major updates)

### **Emergency Maintenance**
1. **Authorization Required**:
   - P1 incidents: Immediate (notify after)
   - P2 incidents: Manager approval
   - P3/P4: Schedule during normal window

2. **Communication**:
   - 2 hours notice (if possible)
   - Status page update
   - User notification email

---

## 🔍 **Monitoring & Alerts**

### **Key Metrics to Monitor**
- **Response time**: < 200ms average
- **Error rate**: < 0.1%
- **CPU usage**: < 80%
- **Memory usage**: < 85%
- **Disk usage**: < 90%
- **Database connections**: < 80% of max

### **Alert Thresholds**
- **Warning**: Metrics reach 70% of limit
- **Critical**: Metrics reach 90% of limit
- **Emergency**: Complete service failure

---

## 📋 **Checklist Templates**

### **Pre-Deployment Checklist**
- [ ] Backup current system
- [ ] Test in staging environment
- [ ] Verify rollback procedure
- [ ] Notify stakeholders
- [ ] Prepare maintenance window
- [ ] Update documentation

### **Post-Deployment Checklist**
- [ ] Verify all services running
- [ ] Test critical functionality
- [ ] Check performance metrics
- [ ] Confirm backup success
- [ ] Update status page
- [ ] Document any issues

### **Incident Resolution Checklist**
- [ ] Identify root cause
- [ ] Apply immediate fix
- [ ] Verify resolution
- [ ] Update monitoring
- [ ] Document lessons learned
- [ ] Schedule follow-up review

---

**📞 Emergency Contact: +1-xxx-xxx-xxxx**
**📧 Operations Email: ops@yourdomain.com**
**🔗 Status Page: https://status.yourdomain.com**

*Last Updated: 2024-01-15*
*Review Schedule: Monthly*
