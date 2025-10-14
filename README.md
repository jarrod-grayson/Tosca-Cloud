# 🧩 Tricentis Tosca Cloud Integration

This repository demonstrates how to integrate **Tricentis Tosca Cloud** with your CI/CD pipelines — enabling fully automated, scalable, and unattended test execution directly from your build or release process.

Tosca Cloud’s open APIs make it easy to trigger Tosca playlists, monitor their progress, and download execution results (such as JUnit XML) for publishing in CI tools like **Azure DevOps**, **GitHub Actions**, **Jenkins**, or **GitLab CI**.

---

## 🚀 Overview

The Tosca CI/CD integration allows you to:
- Trigger Tosca test executions programmatically (no manual input required)
- Integrate automated test runs into any pipeline or orchestration tool
- Fetch JUnit-style results for reporting and quality gates
- Run tests in **Tosca Cloud** environments or your own **on-premise team agents**

This approach minimizes maintenance overhead and accelerates your **Continuous Testing** adoption.

---

## 📘 Official Documentation

- [Tosca Cloud API Reference](https://docs.tricentis.com/tosca-cloud/en-us/content/references/tosca_apis.htm)
- [Tosca Cloud Roles & Permissions](https://docs.tricentis.com/tosca-cloud/en-us/content/references/roles_and_permissions.htm)
- [Getting Started with Tricentis Tosca Cloud](https://docs.tricentis.com/tosca-cloud/en-us/content/get_started.htm)

---

## 🔐 Identity API

> **Endpoint**  
> `https://<your_tenant>.my.tricentis.com/_identity/apiDocs/swagger/index.html`

Use the **Identity API** to authenticate and retrieve your **Client ID** and **Client Secret**, which are required for OAuth 2.0 authentication in Tosca Cloud integrations.

📖 [Guide: How to get your client secret](https://docs.tricentis.com/tosca-cloud/en-us/content/admin_guide/get_client_secret.htm)

---

## 🧠 Playlist API

> **Endpoint**  
> `https://<your_tenant>.my.tricentis.com/_playlists/apiDocs/swagger/index.html`

The **Playlist API** allows you to:
- Trigger test playlist executions
- Monitor their current state (`pending`, `running`, `succeeded`, `failed`, `cancelled`)
- Retrieve and download **JUnit results** once the run completes

**Typical workflow:**
1. Authenticate via the Identity API (using OAuth 2.0)
2. Trigger a playlist with your parameters
3. Poll its state until completion
4. Download JUnit results for publishing to your CI/CD tool

---

## ⚙️ Setting Up Team Agents

Agents are the runtime components that execute your tests.

A **Team Agent** is installed on your premises (for example, a Windows VM or server).  
Unlike personal agents, team agents are shared across your organization and handle parallel executions.

📘 Learn more:
- [Team Agents](https://docs.tricentis.com/tosca-cloud/en-us/content/admin_guide/agents_team.htm)  
- [Running Tests](https://docs.tricentis.com/tosca-cloud/en-us/content/run_tests/run_tests.htm)  
- [Viewing Results](https://docs.tricentis.com/tosca-cloud/en-us/content/run_tests/check_results.htm)

---

## 🧩 Tosca Cloud Architecture

Below is a high-level view of the Tosca Cloud execution flow — showing how your CI/CD pipeline interacts with Tosca Cloud APIs and agents.

<img width="1200" alt="Tosca Cloud Architecture" src="https://github.com/user-attachments/assets/7e0e8bbf-3487-44ff-bc30-fec4da60a19f" />

---

## 🧪 Example Use Case: CI Pipeline Integration

This repository includes example PowerShell scripts (such as `Invoke-ToscaCloudPlaylist.ps1`) to demonstrate:
- Authenticating via Okta (OAuth 2.0 client credentials)
- Triggering a Tosca Cloud Playlist via REST API
- Polling for status until completion
- Downloading and saving JUnit results
- Publishing those results back to a CI tool

**Example YAML snippet for Azure DevOps:**
```yaml
- task: PowerShell@2
  displayName: "Run Tosca Cloud Playlist"
  inputs:
    targetType: 'filePath'
    filePath: 'C:\Tricentis\Tosca\Invoke-ToscaCloudPlaylist.ps1'
    arguments: >
      -TokenUrl "https://yourtenant.okta.com/oauth2/default/v1/token"
      -ClientId "Your_Client_ID"
      -ClientSecret "$(ClientSecret)"
      -Scope "tta"
      -TenantBaseUrl "https://yourtenant.my.tricentis.com/your_space_id"
      -PlaylistId "your-playlist-guid"
      -ResultsFileName "results.xml"
      -ResultsFolderPath "$(Build.ArtifactStagingDirectory)\Results"
