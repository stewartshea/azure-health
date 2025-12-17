#!/usr/bin/env bun

// Super simple Bun example - validates that Bun works
console.log("✅ Bun is working!");
console.log(`Node version: ${process.version}`);
console.log(`Platform: ${process.platform}`);
console.log(`Architecture: ${process.arch}`);
console.log(`Current time: ${new Date().toISOString()}`);

// Simple validation
if (typeof Bun !== 'undefined') {
  console.log("✅ Bun runtime detected");
} else {
  console.log("❌ Bun runtime not detected");
  process.exit(1);
}

// Create issues.json file
const issues = [
  {
    "title": "High CPU Usage Detected",
    "severity": 2,
    "expected": "CPU usage should be below 80%",
    "actual": "CPU usage is at 95%",
    "reproduce_hint": "Check the system metrics for CPU usage",
    "next_steps": "1. Identify the process consuming CPU\n2. Consider scaling resources\n3. Investigate potential CPU leaks",
    "details": "CPU usage has exceeded threshold for the past 15 minutes.\nAverage: 95%\nPeak: 98%"
  },
  {
    "title": "Memory Usage Warning",
    "severity": 3,
    "expected": "Memory usage should be below 70%",
    "actual": "Memory usage is at 78%",
    "reproduce_hint": "Check memory metrics",
    "next_steps": "Monitor memory usage and consider increasing memory allocation if trend continues",
    "details": "Memory usage is approaching threshold.\nCurrent: 78%\nTrend: Increasing"
  }
];

// Write issues.json file
await Bun.write("issues.json", JSON.stringify(issues, null, 2));
console.log("✅ Created issues.json file");

