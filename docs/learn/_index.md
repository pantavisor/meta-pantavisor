+++
title = "Learn Pantavisor"
weight = 1

# SEO Configuration
description = "Comprehensive learning resources for embedded systems developers, IoT product managers, and DevOps engineers using Pantavisor containerization."
keywords = ["learn pantavisor", "embedded linux tutorial", "iot containerization guide", "embedded devops", "container orchestration tutorial", "embedded systems education", "pantavisor documentation", "iot development guide", "embedded linux containers tutorial", "containerized embedded development"]
meta_description = "Learn Pantavisor: Complete guide to containerized embedded Linux development. Tutorials for IoT developers, embedded engineers, and DevOps teams."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Learn Pantavisor - Embedded Linux Container Tutorial"
og_description = "Master containerized embedded development with comprehensive tutorials and guides for IoT engineers and DevOps teams."
og_type = "website"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Learn Pantavisor - Embedded Container Development"
twitter_description = "Complete guide to containerized embedded Linux development and IoT device management"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.9
sitemap_changefreq = "weekly"
canonical_url = "https://www.pantavisor.io/learn/"

[params]
  menuPre = '<i class="fa-fw fas fa-graduation-cap"></i> '
+++

<style>
.learn-hero {
  background: linear-gradient(135deg, #1976d2 0%, #1565c0 100%);
  color: white;
  padding: 60px 40px;
  margin-bottom: 60px;
  border-radius: 8px;
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

.learn-hero h1 {
  font-size: 3rem;
  font-weight: 700;
  margin-bottom: 20px;
  color: white;
}

.learn-hero .subtitle {
  font-size: 1.25rem;
  line-height: 1.6;
  margin-bottom: 30px;
  opacity: 0.95;
}

.cta-buttons {
  display: flex;
  gap: 15px;
  flex-wrap: wrap;
}

.btn {
  padding: 12px 32px;
  font-size: 1rem;
  font-weight: 600;
  border-radius: 6px;
  transition: all 0.3s ease;
  text-decoration: none;
  display: inline-block;
}

.btn-primary-light {
  background-color: white;
  color: #1976d2;
}

.btn-primary-light:hover {
  background-color: #f5f5f5;
  transform: translateY(-2px);
  box-shadow: 0 6px 12px rgba(0, 0, 0, 0.15);
}

.btn-outline-light {
  background-color: transparent;
  color: white;
  border: 2px solid white;
}

.btn-outline-light:hover {
  background-color: rgba(255, 255, 255, 0.1);
  transform: translateY(-2px);
}

.learning-paths {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 30px;
  margin: 60px 0;
}

.path-card {
  background: white;
  border: 1px solid #e0e0e0;
  border-radius: 8px;
  padding: 30px;
  transition: all 0.3s ease;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
}

.path-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 16px rgba(0, 0, 0, 0.1);
  border-color: #1976d2;
}

.path-card .icon {
  font-size: 2.5rem;
  color: #1976d2;
  margin-bottom: 15px;
}

.path-card h3 {
  font-size: 1.5rem;
  margin-bottom: 15px;
  color: #333;
  font-weight: 600;
}

.path-card p {
  color: #666;
  line-height: 1.6;
  margin-bottom: 20px;
}

.path-card .btn-learn {
  display: inline-block;
  color: #1976d2;
  text-decoration: none;
  font-weight: 600;
  transition: all 0.3s ease;
}

.path-card .btn-learn:hover {
  color: #1565c0;
  transform: translateX(4px);
}

.features-grid {
  background: #f8f9fa;
  padding: 40px;
  border-radius: 8px;
  margin: 40px 0;
}

.features-grid h2 {
  text-align: center;
  margin-bottom: 40px;
  font-size: 2rem;
  font-weight: 700;
  color: #333;
}

.features-list {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 25px;
}

.feature-item {
  background: white;
  padding: 25px;
  border-radius: 6px;
  border-left: 4px solid #1976d2;
}

.feature-item .icon {
  font-size: 2rem;
  color: #1976d2;
  margin-bottom: 12px;
}

.feature-item h4 {
  font-size: 1.1rem;
  margin-bottom: 10px;
  color: #333;
  font-weight: 600;
}

.feature-item p {
  color: #666;
  font-size: 0.95rem;
  line-height: 1.5;
}

.badge-group {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  margin: 20px 0;
}

.badge-tag {
  background: #e3f2fd;
  color: #1976d2;
  padding: 6px 14px;
  border-radius: 20px;
  font-size: 0.85rem;
  font-weight: 500;
}

.divider {
  height: 2px;
  background: linear-gradient(90deg, transparent, #1976d2, transparent);
  margin: 50px 0;
}
</style>

<div class="learn-hero">
  <div class="container">
    <p class="subtitle">
      Master containerized embedded Linux development with comprehensive tutorials and hands-on guides. Perfect for IoT developers, embedded engineers, and DevOps teams.
    </p>
    <div class="cta-buttons">
      <a href="/learn/concepts/" class="btn btn-primary-light">Start with Concepts</a>
      <a href="/learn/device-setup/" class="btn btn-outline-light">Quick Start Guide</a>
    </div>
  </div>
</div>

## Learning Paths

Choose your path based on your role and experience level:

<div class="learning-paths">
  <div class="path-card">
    <div class="icon"><i class="fas fa-lightbulb"></i></div>
    <h3>Core Concepts</h3>
    <p>Understand the fundamentals of Pantavisor, containerization in embedded systems, and DevOps principles for IoT.</p>
    <a href="/learn/concepts/" class="btn-learn">Explore Concepts →</a>
  </div>

  <div class="path-card">
    <div class="icon"><i class="fas fa-rocket"></i></div>
    <h3>Quick Start</h3>
    <p>Get your device up and running with Pantavisor. Flash, connect, and deploy your first application in minutes.</p>
    <a href="/learn/device-setup/" class="btn-learn">Start Setup →</a>
  </div>

  <div class="path-card">
    <div class="icon"><i class="fas fa-hammer"></i></div>
    <h3>Build Pantavisor</h3>
    <p>Build custom Pantavisor images for your specific hardware. Learn about build systems and target configuration.</p>
    <a href="/learn/build/" class="btn-learn">View Build Guide →</a>
  </div>

  <div class="path-card">
    <div class="icon"><i class="fas fa-microchip"></i></div>
    <h3>Porting Guide</h3>
    <p>Port Pantavisor to new hardware platforms. Understand machine configurations and platform requirements.</p>
    <a href="/learn/port/" class="btn-learn">Learn Porting →</a>
  </div>

  <div class="path-card">
    <div class="icon"><i class="fas fa-wrench"></i></div>
    <h3>Troubleshooting</h3>
    <p>Find solutions to common issues and learn best practices. Access FAQs and community support resources.</p>
    <a href="/learn/troubleshooting/" class="btn-learn">Find Solutions →</a>
  </div>
</div>

<div class="divider"></div>

<div class="features-grid">
  <h2>What You'll Master</h2>

  <div class="features-list">
  <div class="feature-item">
    <div class="icon"><i class="fas fa-sd-card"></i></div>
    <h4>Device Setup</h4>
    <p>Flash Pantavisor Linux onto your device and establish secure connections through various access methods.</p>
  </div>

  <div class="feature-item">
    <div class="icon"><i class="fas fa-box"></i></div>
    <h4>Container Management</h4>
    <p>Install, configure, modify, and manage containerized applications on your embedded devices.</p>
  </div>

  <div class="feature-item">
    <div class="icon"><i class="fas fa-cloud-upload-alt"></i></div>
    <h4>OTA Updates</h4>
    <p>Deploy secure over-the-air updates and manage application versions across your device fleet.</p>
  </div>

  <div class="feature-item">
    <div class="icon"><i class="fas fa-tools"></i></div>
    <h4>SDK & Tools</h4>
    <p>Leverage PVR-SDK and command-line tools to accelerate your development workflow.</p>
  </div>

  <div class="feature-item">
    <div class="icon"><i class="fas fa-network-wired"></i></div>
    <h4>Network Access</h4>
    <p>Connect via local networks, serial ports, or remote management through Pantahub cloud services.</p>
  </div>

  <div class="feature-item">
    <div class="icon"><i class="fas fa-book"></i></div>
    <h4>Deep Dives</h4>
    <p>Understand architecture, build systems, and advanced porting techniques for production deployments.</p>
  </div>
  </div>
</div>

<div class="divider"></div>

## How to Use These Resources

1. **New to Pantavisor?** Start with [Core Concepts](/learn/concepts/) to understand the fundamentals
2. **Ready to get hands-on?** Jump to [Quick Start](/learn/device-setup/) to set up your first device
3. **Building custom images?** Explore [Build Pantavisor](/learn/build/) for detailed build instructions
4. **Supporting new hardware?** Check out [Porting Guide](/learn/port/) for platform integration
5. **Hit a snag?** Visit [Troubleshooting](/learn/troubleshooting/) for FAQs and solutions

<div class="badge-group" style="margin-top: 40px; justify-content: center;">
  <span class="badge-tag"><i class="fas fa-graduation-cap"></i> Educational</span>
  <span class="badge-tag"><i class="fas fa-code"></i> Hands-On</span>
  <span class="badge-tag"><i class="fas fa-book"></i> Comprehensive</span>
  <span class="badge-tag"><i class="fas fa-community"></i> Community Driven</span>
</div>
