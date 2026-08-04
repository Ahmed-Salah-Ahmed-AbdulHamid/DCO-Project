#!/bin/bash
# ==========================================================================
# setup_cloudwatch_agent.sh
# DCO Phase 4: CloudWatch Unified Agent — Install & Configure
#
# Target: Ubuntu 22.04 LTS EC2 Instance
# Run as: sudo bash setup_cloudwatch_agent.sh
# ==========================================================================

set -euxo pipefail

echo "============================================================"
echo "  DCO — CloudWatch Agent Installation & Configuration"
echo "============================================================"

# ------------------------------------------------------------------
# 1. Download and install the CloudWatch Unified Agent
# ------------------------------------------------------------------
echo ">>> [1/5] Downloading CloudWatch Agent .deb package..."
cd /tmp
wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb

echo ">>> [2/5] Installing CloudWatch Agent..."
dpkg -i -E amazon-cloudwatch-agent.deb
rm -f amazon-cloudwatch-agent.deb

# ------------------------------------------------------------------
# 2. Write the agent configuration file
# ------------------------------------------------------------------
echo ">>> [3/5] Writing agent configuration..."

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'AGENT_CONFIG'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "namespace": "DCO_Project_Metrics",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}",
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}"
    },
    "aggregation_dimensions": [
      ["InstanceId"],
      ["InstanceType"],
      []
    ],
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system",
          "cpu_usage_iowait",
          "cpu_usage_steal"
        ],
        "metrics_collection_interval": 30,
        "totalcpu": true,
        "resources": ["*"]
      },
      "mem": {
        "measurement": [
          "mem_used_percent",
          "mem_used",
          "mem_total",
          "mem_available",
          "mem_available_percent"
        ],
        "metrics_collection_interval": 30
      },
      "disk": {
        "measurement": [
          "disk_used_percent",
          "disk_free",
          "disk_total"
        ],
        "metrics_collection_interval": 60,
        "resources": ["/"],
        "ignore_file_system_types": [
          "sysfs", "devtmpfs", "tmpfs", "overlay"
        ]
      },
      "diskio": {
        "measurement": [
          "diskio_reads",
          "diskio_writes",
          "diskio_read_bytes",
          "diskio_write_bytes"
        ],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "net": {
        "measurement": [
          "net_bytes_sent",
          "net_bytes_recv",
          "net_packets_sent",
          "net_packets_recv"
        ],
        "metrics_collection_interval": 60,
        "resources": ["eth0"]
      },
      "swap": {
        "measurement": [
          "swap_used_percent",
          "swap_used",
          "swap_free"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/dco/ec2/syslog",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "/dco/ec2/cloud-init",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          }
        ]
      }
    }
  }
}
AGENT_CONFIG

# ------------------------------------------------------------------
# 3. Attach the CloudWatch IAM policy (if not already attached)
# ------------------------------------------------------------------
echo ">>> [4/5] Verifying IAM permissions..."
echo "    NOTE: The EC2 instance profile must include the"
echo "    'CloudWatchAgentServerPolicy' managed policy."
echo "    If not attached, run:"
echo ""
echo "    aws iam attach-role-policy \\"
echo "      --role-name dco-ec2-role \\"
echo "      --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
echo ""

# ------------------------------------------------------------------
# 4. Start the CloudWatch Agent
# ------------------------------------------------------------------
echo ">>> [5/5] Starting CloudWatch Agent..."
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# ------------------------------------------------------------------
# 5. Verify the agent is running
# ------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Agent Status:"
echo "============================================================"
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a status

echo ""
echo "✅ CloudWatch Agent installed and running!"
echo "   Namespace: DCO_Project_Metrics"
echo "   Interval:  30s (CPU, Memory) / 60s (Disk, Network)"
echo "   Logs:      /dco/ec2/syslog, /dco/ec2/cloud-init"
echo ""
echo "   View metrics in the AWS Console:"
echo "   CloudWatch → Metrics → Custom Namespaces → DCO_Project_Metrics"
