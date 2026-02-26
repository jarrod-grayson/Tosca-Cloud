# 🚀 Tricentis Tosca Cloud CI/CD Integration (Reference)

This repository demonstrates how to trigger and monitor **Tosca Cloud Playlist executions** from CI/CD pipelines such as:

- Azure DevOps  
- GitHub Actions  
- Jenkins  
- GitLab CI  

It uses Tosca Cloud’s public REST APIs to start executions, monitor progress, and download results for reporting.

---

## 🔗 Reference Script Source

The PowerShell script in this repository is based on the Tricentis sample:

**KB Article:**  
[Tosca Cloud Playlist API sample script (KB0022297)](https://support-hub.tricentis.com/open?id=kb_article_view&sysparm_article=KB0022297)

This repo provides a **pipeline-ready implementation** and examples for CI/CD usage.

---

## 🧠 What This Integration Does

From a pipeline, the script will:

1. Authenticate to Tosca Cloud (OAuth2 client credentials)  
2. Find a Playlist by name  
3. Start a new Playlist run  
4. Monitor until completion  
5. Download JUnit results  
6. Publish results back to the pipeline  

No manual interaction required.

---

## 🏗 High-Level Flow

CI Pipeline → PowerShell Script → Tosca Cloud API → Team Agents execute tests → Results returned to pipeline

---

## 🔐 Prerequisites

You will need:

- Tosca Cloud tenant URL  
- Client ID  
- Client Secret  
- Space ID  
- Playlist name  
- Team Agent configured and online  

Documentation:  
https://docs.tricentis.com/tosca-cloud/en-us/content/get_started.htm

---

## ▶ Example Azure DevOps Usage

```yaml
- task: PowerShell@2
  displayName: Execute Tosca Playlist
  inputs:
    filePath: $(System.DefaultWorkingDirectory)\tosca_cloud_execution_client.ps1
    arguments: >
      -BaseUrl "https://$(ToscaTenant).my.tricentis.com"
      -ClientId "$(ToscaClientId)"
      -ClientSecret "$(ToscaClientSecret)"
      -TokenUrl "$(ToscaAuthURL)"
      -SpaceId "$(ToscaWorkspaceID)"
      -PlaylistName "Smoke"
      -StartNewRun
      -MonitorRun
      -RetrieveResults
      -JUnitResultsFile "$(Agent.TempDirectory)\results.xml"
```

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
