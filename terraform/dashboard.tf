# ==========================================================================
# dashboard.tf — Enhanced CloudWatch Dashboard for DCO Resource Monitoring
# DCO Phase 4+: Monitoring & Optimization
#
# Widgets:
#   1. Header
#   2. Live CPU Utilization (Gauge + Line)
#   3. Live RAM Utilization (Gauge + Line)
#   4. Active Running Instances (Metric Math — SAMPLE_COUNT)
#   5. Network Traffic (In/Out)
#   6. Disk Utilization
#   7. CPU Credit Balance (T-series)
# ==========================================================================

# --------------------------------------------------------------------------
# CloudWatch Dashboard
# --------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "dco_monitor" {
  dashboard_name = "DCO-Resource-Monitor"

  dashboard_body = jsonencode({
    widgets = [

      # ==================================================================
      # Row 0: Title / Header
      # ==================================================================
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# 🖥️ DCO Resource Monitor\nReal-time infrastructure metrics for the **DevOps-Enabled Cloud Resource Optimizer** | Instance: `${aws_instance.dco_server.id}` (`${var.instance_type}`)"
        }
      },

      # ==================================================================
      # Row 1 (Left): CPU Utilization — Gauge (instant view)
      # ==================================================================
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 6
        height = 6
        properties = {
          title  = "🔥 CPU Utilization (Live)"
          region = var.aws_region
          view   = "gauge"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.dco_server.id, { label = "CPU %" }]
          ]
          yAxis = {
            left = { min = 0, max = 100 }
          }
          annotations = {
            horizontal = [
              { color = "#2ca02c", value = 0 },
              { color = "#ff9900", value = 70 },
              { color = "#d13212", value = 90 }
            ]
          }
        }
      },

      # ==================================================================
      # Row 1 (Center-Left): CPU Utilization — Time Series (trend)
      # ==================================================================
      {
        type   = "metric"
        x      = 6
        y      = 1
        width  = 10
        height = 6
        properties = {
          title  = "CPU Utilization — Trend (Agent Breakdown)"
          region = var.aws_region
          view   = "timeSeries"
          stacked = true
          period = 60
          stat   = "Average"
          metrics = [
            ["DCO_Project_Metrics", "cpu_usage_user", "InstanceId", aws_instance.dco_server.id, { label = "User %", color = "#1f77b4" }],
            ["DCO_Project_Metrics", "cpu_usage_system", "InstanceId", aws_instance.dco_server.id, { label = "System %", color = "#ff7f0e" }],
            ["DCO_Project_Metrics", "cpu_usage_iowait", "InstanceId", aws_instance.dco_server.id, { label = "IO Wait %", color = "#9467bd" }],
            ["DCO_Project_Metrics", "cpu_usage_steal", "InstanceId", aws_instance.dco_server.id, { label = "Steal %", color = "#d62728" }]
          ]
          yAxis = {
            left = { min = 0, max = 100, label = "Percent" }
          }
          annotations = {
            horizontal = [
              { label = "⚠️ Warning", value = 70, color = "#ff9900", fill = "none" },
              { label = "🔴 Critical", value = 90, color = "#d13212", fill = "above" }
            ]
          }
        }
      },

      # ==================================================================
      # Row 1 (Right): Active Running Instances — Metric Math
      # Uses SAMPLE_COUNT of CPUUtilization: if the instance is
      # reporting metrics → 1, if stopped → 0 (no data).
      # METRICS(m1) counts data points; IF(m1>0,1,0) normalises to 1/0.
      # ==================================================================
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "🟢 Active Running Instances"
          region = var.aws_region
          view   = "singleValue"
          period = 300
          stat   = "SampleCount"
          sparkline = true
          setPeriodToTimeRange = false
          metrics = [
            # m1: raw metric — CPUUtilization sample count
            [
              "AWS/EC2", "CPUUtilization",
              "InstanceId", aws_instance.dco_server.id,
              { id = "m1", visible = false, stat = "SampleCount" }
            ],
            # e1: Metric Math — normalise to 1 if any data points exist
            [
              { expression = "IF(m1 > 0, 1, 0)", label = "Running Instances", id = "e1", color = "#2ca02c" }
            ]
          ]
        }
      },

      # ==================================================================
      # Row 2 (Left): RAM Utilization — Gauge (instant view)
      # ==================================================================
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 6
        height = 6
        properties = {
          title  = "💾 RAM Utilization (Live)"
          region = var.aws_region
          view   = "gauge"
          period = 60
          stat   = "Average"
          metrics = [
            ["DCO_Project_Metrics", "mem_used_percent", "InstanceId", aws_instance.dco_server.id, { label = "RAM %" }]
          ]
          yAxis = {
            left = { min = 0, max = 100 }
          }
          annotations = {
            horizontal = [
              { color = "#2ca02c", value = 0 },
              { color = "#ff9900", value = 70 },
              { color = "#d13212", value = 85 }
            ]
          }
        }
      },

      # ==================================================================
      # Row 2 (Center-Left): RAM Utilization — Time Series (trend)
      # ==================================================================
      {
        type   = "metric"
        x      = 6
        y      = 7
        width  = 10
        height = 6
        properties = {
          title  = "Memory Utilization — Trend"
          region = var.aws_region
          view   = "timeSeries"
          stacked = false
          period = 60
          stat   = "Average"
          metrics = [
            ["DCO_Project_Metrics", "mem_used_percent", "InstanceId", aws_instance.dco_server.id, { label = "Used %", color = "#d13212" }],
            ["DCO_Project_Metrics", "mem_available_percent", "InstanceId", aws_instance.dco_server.id, { label = "Available %", color = "#2ca02c" }]
          ]
          yAxis = {
            left = { min = 0, max = 100, label = "Percent" }
          }
          annotations = {
            horizontal = [
              { label = "⚠️ Warning (70%)", value = 70, color = "#ff9900", fill = "none" },
              { label = "🔴 Critical (85%)", value = 85, color = "#d13212", fill = "above" }
            ]
          }
        }
      },

      # ==================================================================
      # Row 2 (Right): Memory — Absolute (stacked area)
      # ==================================================================
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "Memory — Absolute (Used vs Available)"
          region = var.aws_region
          view   = "timeSeries"
          stacked = true
          period = 60
          stat   = "Average"
          metrics = [
            ["DCO_Project_Metrics", "mem_used", "InstanceId", aws_instance.dco_server.id, { label = "Used (bytes)", color = "#d62728" }],
            ["DCO_Project_Metrics", "mem_available", "InstanceId", aws_instance.dco_server.id, { label = "Available (bytes)", color = "#2ca02c" }]
          ]
        }
      },

      # ==================================================================
      # Row 3 (Left): Network Traffic — In/Out (AWS/EC2 namespace)
      # ==================================================================
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "🌐 Network Traffic (AWS/EC2)"
          region = var.aws_region
          view   = "timeSeries"
          stacked = false
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.dco_server.id, { label = "Network In (bytes)", color = "#1f77b4" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.dco_server.id, { label = "Network Out (bytes)", color = "#ff7f0e" }]
          ]
          yAxis = {
            left = { label = "Bytes" }
          }
        }
      },

      # ==================================================================
      # Row 3 (Right): Network Traffic — Agent (eth0, higher resolution)
      # ==================================================================
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "🌐 Network Traffic — Agent (eth0, 60s resolution)"
          region = var.aws_region
          view   = "timeSeries"
          stacked = false
          period = 60
          stat   = "Average"
          metrics = [
            ["DCO_Project_Metrics", "net_bytes_recv", "InstanceId", aws_instance.dco_server.id, "interface", "eth0", { label = "Bytes Received", color = "#1f77b4" }],
            ["DCO_Project_Metrics", "net_bytes_sent", "InstanceId", aws_instance.dco_server.id, "interface", "eth0", { label = "Bytes Sent", color = "#ff7f0e" }],
            ["DCO_Project_Metrics", "net_packets_recv", "InstanceId", aws_instance.dco_server.id, "interface", "eth0", { label = "Packets In", color = "#2ca02c" }],
            ["DCO_Project_Metrics", "net_packets_sent", "InstanceId", aws_instance.dco_server.id, "interface", "eth0", { label = "Packets Out", color = "#d62728" }]
          ]
        }
      },

      # ==================================================================
      # Row 4 (Left): Disk Utilization
      # ==================================================================
      {
        type   = "metric"
        x      = 0
        y      = 19
        width  = 8
        height = 6
        properties = {
          title  = "💿 Disk Utilization (/)"
          region = var.aws_region
          view   = "timeSeries"
          stacked = false
          period = 60
          stat   = "Average"
          metrics = [
            ["DCO_Project_Metrics", "disk_used_percent", "InstanceId", aws_instance.dco_server.id, "path", "/", "fstype", "ext4", { label = "Disk Used %", color = "#e377c2" }]
          ]
          yAxis = {
            left = { min = 0, max = 100, label = "Percent" }
          }
          annotations = {
            horizontal = [
              { label = "⚠️ 80%", value = 80, color = "#ff9900" }
            ]
          }
        }
      },

      # ==================================================================
      # Row 4 (Center): Swap Usage
      # ==================================================================
      {
        type   = "metric"
        x      = 8
        y      = 19
        width  = 8
        height = 6
        properties = {
          title  = "Swap Usage"
          region = var.aws_region
          view   = "timeSeries"
          stacked = false
          period = 60
          stat   = "Average"
          metrics = [
            ["DCO_Project_Metrics", "swap_used_percent", "InstanceId", aws_instance.dco_server.id, { label = "Swap Used %", color = "#8c564b" }]
          ]
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },

      # ==================================================================
      # Row 4 (Right): CPU Credit Balance (T-series burstable)
      # ==================================================================
      {
        type   = "metric"
        x      = 16
        y      = 19
        width  = 8
        height = 6
        properties = {
          title  = "⚡ CPU Credit Balance (T-series)"
          region = var.aws_region
          view   = "timeSeries"
          stacked = false
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUCreditBalance", "InstanceId", aws_instance.dco_server.id, { label = "Credits Remaining", color = "#2ca02c" }],
            ["AWS/EC2", "CPUCreditUsage", "InstanceId", aws_instance.dco_server.id, { label = "Credits Used", color = "#d62728" }]
          ]
        }
      }
    ]
  })
}

# --------------------------------------------------------------------------
# CloudWatch Alarms — CPU & Memory
# --------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  alarm_description   = "CPU utilisation exceeded 80% for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 80
  period              = 300
  statistic           = "Average"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions = {
    InstanceId = aws_instance.dco_server.id
  }
  treat_missing_data = "notBreaching"

  tags = {
    Name = "${var.project_name}-cpu-high-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${var.project_name}-memory-high"
  alarm_description   = "Memory utilisation exceeded 85% for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 85
  period              = 300
  statistic           = "Average"
  namespace           = "DCO_Project_Metrics"
  metric_name         = "mem_used_percent"
  dimensions = {
    InstanceId = aws_instance.dco_server.id
  }
  treat_missing_data = "notBreaching"

  tags = {
    Name = "${var.project_name}-memory-high-alarm"
  }
}
