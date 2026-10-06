#!/usr/bin/env python3
import base64
import os

ICONS_DIR = "/Users/limkeunhyeok/workspace/homelab-infra/docs/icons"

def get_base64_svg(filename):
    path = os.path.join(ICONS_DIR, filename)
    with open(path, "rb") as f:
        data = f.read()
    return "data:image/svg+xml;base64," + base64.b64encode(data).decode("utf-8")

# 쿠버네티스 공식 커뮤니티 아이콘 로드
icon_user = get_base64_svg("user.svg")
icon_ing = get_base64_svg("ing.svg")
icon_deploy = get_base64_svg("deploy.svg")
icon_sts = get_base64_svg("sts.svg")
icon_secret = get_base64_svg("secret.svg")

# GitHub SVG icon
github_svg = '''data:image/svg+xml;base64,''' + base64.b64encode(b'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#334155"><path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z"/></svg>''').decode("utf-8")

html_content = f'''<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <style>
    * {{
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }}
    body {{
      background-color: #ffffff;
      display: flex;
      justify-content: center;
      align-items: center;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      padding: 30px;
    }}
  </style>
</head>
<body>

<svg width="1160" height="640" viewBox="0 0 1160 640" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- Arrow Markers (ex2.png style) -->
    <marker id="arrow" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 1 2 L 7 5 L 1 8 z" fill="#334155"/>
    </marker>
    <marker id="arrow-blue" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 1 2 L 7 5 L 1 8 z" fill="#2563eb"/>
    </marker>
    <marker id="arrow-green" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 1 2 L 7 5 L 1 8 z" fill="#059669"/>
    </marker>
  </defs>

  <!-- ========================================== -->
  <!-- 1. USER / CLIENT (좌측 - Traefik과 수평 정렬) -->
  <!-- ========================================== -->
  <g transform="translate(60, 110)">
    <image href="{icon_user}" x="-24" y="-32" width="48" height="48"/>
    <text x="0" y="28" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">User / Client</text>
    <text x="0" y="42" text-anchor="middle" font-size="10.5" fill="#64748b">MacBook Browser</text>
  </g>

  <!-- ========================================== -->
  <!-- 2. K3S CLUSTER (중앙 메인 클러스터)        -->
  <!-- ========================================== -->
  <rect x="180" y="30" width="700" height="580" rx="4" fill="none" stroke="#cbd5e1" stroke-width="1.2"/>
  
  <!-- 클러스터 상단 헤더 라벨 태그 -->
  <rect x="180" y="30" width="280" height="26" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.2"/>
  <rect x="181" y="55" width="278" height="2" fill="#f8fafc"/>
  <text x="195" y="48" font-size="11.5" font-weight="700" fill="#334155">k3s Cluster</text>
  <text x="268" y="48" font-size="10.5" fill="#64748b">(Windows WSL2 • 192.168.0.10)</text>

  <!-- ========================================== -->
  <!-- 1층: INGRESS & SSO (클러스터 상단)          -->
  <!-- ========================================== -->
  <!-- Traefik Ingress Controller -->
  <g transform="translate(300, 110)">
    <image href="{icon_ing}" x="-25" y="-30" width="50" height="50"/>
    <text x="0" y="32" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">Traefik Ingress</text>
    <text x="0" y="46" text-anchor="middle" font-size="10" fill="#64748b">Port :443 (TLS)</text>
  </g>

  <!-- Authelia SSO (ForwardAuth) -->
  <g transform="translate(560, 110)">
    <image href="{icon_secret}" x="-25" y="-30" width="50" height="50"/>
    <text x="0" y="32" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">Authelia SSO</text>
    <text x="0" y="46" text-anchor="middle" font-size="10" fill="#64748b">ForwardAuth Filter</text>
  </g>

  <!-- ========================================== -->
  <!-- 2층: NAMESPACE: apps (점선 사각 박스)      -->
  <!-- ========================================== -->
  <g transform="translate(210, 195)">
    <!-- 네임스페이스 상단 헤더 바 -->
    <rect x="0" y="0" width="640" height="24" fill="#f1f5f9" stroke="#cbd5e1" stroke-width="1"/>
    <text x="20" y="16" font-size="11" font-weight="700" fill="#334155">Namespace: apps</text>

    <!-- 점선 본체 테두리 -->
    <rect x="0" y="24" width="640" height="150" fill="none" stroke="#60a5fa" stroke-width="1.2" stroke-dasharray="4 4"/>

    <!-- Frontend Pod (React 19) -->
    <g transform="translate(90, 85)">
      <image href="{icon_deploy}" x="-25" y="-30" width="50" height="50"/>
      <text x="0" y="32" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">Frontend</text>
      <text x="0" y="46" text-anchor="middle" font-size="10" fill="#64748b">React 19 • Vite</text>
    </g>

    <!-- Backend Pod (NestJS 12) -->
    <g transform="translate(350, 85)">
      <image href="{icon_deploy}" x="-25" y="-30" width="50" height="50"/>
      <text x="0" y="32" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">Backend</text>
      <text x="0" y="46" text-anchor="middle" font-size="10" fill="#64748b">NestJS 12 • Prisma</text>
    </g>

    <!-- Frontend -> Backend 화살표 (④ REST API) -->
    <path d="M 130 85 L 305 85" fill="none" stroke="#334155" stroke-width="1.3" marker-end="url(#arrow)"/>
    <circle cx="215" cy="85" r="9" fill="#f1f5f9" stroke="#cbd5e1" stroke-width="1"/>
    <text x="215" y="88.5" text-anchor="middle" font-size="9.5" font-weight="700" fill="#475569">4</text>
    <rect x="185" y="64" width="60" height="14" fill="#ffffff"/>
    <text x="215" y="74" text-anchor="middle" font-size="9.5" font-weight="600" fill="#475569">REST API</text>
  </g>

  <!-- ========================================== -->
  <!-- 3층: NAMESPACE: infra (점선 사각 박스)     -->
  <!-- ========================================== -->
  <g transform="translate(210, 400)">
    <!-- 네임스페이스 상단 헤더 바 -->
    <rect x="0" y="0" width="640" height="24" fill="#f1f5f9" stroke="#cbd5e1" stroke-width="1"/>
    <text x="20" y="16" font-size="11" font-weight="700" fill="#334155">Namespace: infra</text>

    <!-- 점선 본체 테두리 -->
    <rect x="0" y="24" width="640" height="175" fill="none" stroke="#60a5fa" stroke-width="1.2" stroke-dasharray="4 4"/>

    <!-- PostgreSQL (50Gi) -->
    <g transform="translate(90, 95)">
      <image href="{icon_sts}" x="-25" y="-30" width="50" height="50"/>
      <text x="0" y="32" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">PostgreSQL</text>
      <text x="0" y="46" text-anchor="middle" font-size="10" fill="#64748b">StatefulSet (50Gi)</text>
    </g>

    <!-- MinIO S3 (100Gi) -->
    <g transform="translate(320, 95)">
      <image href="{icon_sts}" x="-25" y="-30" width="50" height="50"/>
      <text x="0" y="32" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">MinIO S3</text>
      <text x="0" y="46" text-anchor="middle" font-size="10" fill="#64748b">StatefulSet (100Gi)</text>
    </g>

    <!-- OpenSearch (10Gi) -->
    <g transform="translate(540, 95)">
      <image href="{icon_sts}" x="-25" y="-30" width="50" height="50"/>
      <text x="0" y="32" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">OpenSearch</text>
      <text x="0" y="46" text-anchor="middle" font-size="10" fill="#64748b">StatefulSet (10Gi)</text>
    </g>

    <!-- 볼륨 스토리지 안내 텍스트 -->
    <text x="320" y="182" text-anchor="middle" font-size="10" fill="#64748b">Persistent Volume: Rancher local-path Provisioner → Host NVMe Storage</text>
  </g>

  <!-- ========================================== -->
  <!-- 4. GITOPS & CI/CD (우측 영역)              -->
  <!-- ========================================== -->
  <g transform="translate(925, 80)">
    <!-- 상단 헤더 바 -->
    <rect x="0" y="0" width="195" height="24" fill="#f1f5f9" stroke="#cbd5e1" stroke-width="1"/>
    <text x="97" y="16" text-anchor="middle" font-size="11" font-weight="700" fill="#334155">GitOps &amp; CI/CD</text>

    <!-- 점선 본체 테두리 -->
    <rect x="0" y="24" width="195" height="495" fill="none" stroke="#94a3b8" stroke-width="1.2" stroke-dasharray="4 4"/>

    <!-- GitHub Repos -->
    <g transform="translate(97, 85)">
      <image href="{github_svg}" x="-22" y="-26" width="44" height="44"/>
      <text x="0" y="30" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">GitHub Repos</text>
      <text x="0" y="44" text-anchor="middle" font-size="9.5" fill="#64748b">homelab-infra / apps</text>
    </g>

    <!-- Push Arrow -->
    <path d="M 97 145 L 97 190" fill="none" stroke="#475569" stroke-width="1.2" marker-end="url(#arrow)"/>
    <text x="106" y="172" font-size="9.5" fill="#64748b">Push</text>

    <!-- GitHub Actions -->
    <g transform="translate(97, 230)">
      <text x="0" y="0" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">GitHub Actions</text>
      <text x="0" y="16" text-anchor="middle" font-size="9.5" fill="#64748b">Automated CI</text>
      <text x="0" y="30" text-anchor="middle" font-size="9" fill="#94a3b8">Build &amp; Push Docker Hub</text>
    </g>

    <!-- Sync Arrow -->
    <path d="M 97 275 L 97 325" fill="none" stroke="#475569" stroke-width="1.2" marker-end="url(#arrow)"/>

    <!-- ArgoCD -->
    <g transform="translate(97, 375)">
      <image href="{icon_deploy}" x="-24" y="-28" width="48" height="48"/>
      <text x="0" y="30" text-anchor="middle" font-size="12" font-weight="700" fill="#1e293b">ArgoCD</text>
      <text x="0" y="44" text-anchor="middle" font-size="9.5" fill="#64748b">GitOps Controller</text>
    </g>
  </g>

  <!-- ========================================== -->
  <!-- 5. 연결선 & 직각 화살표 라우팅              -->
  <!-- ========================================== -->

  <!-- (1) User -> Traefik Ingress: 수평 직선! -->
  <path d="M 110 110 L 265 110" fill="none" stroke="#334155" stroke-width="1.3" marker-end="url(#arrow)"/>
  <circle cx="187" cy="110" r="9" fill="#f1f5f9" stroke="#cbd5e1" stroke-width="1"/>
  <text x="187" y="113.5" text-anchor="middle" font-size="9.5" font-weight="700" fill="#475569">1</text>
  <rect x="158" y="88" width="58" height="15" fill="#ffffff"/>
  <text x="187" y="99" text-anchor="middle" font-size="9.5" font-weight="600" fill="#475569">HTTPS :443</text>

  <!-- (2) Traefik <-> Authelia SSO: 수평 양방향 점선 -->
  <path d="M 345 110 L 525 110" fill="none" stroke="#2563eb" stroke-width="1.2" stroke-dasharray="3 3" marker-end="url(#arrow-blue)"/>
  <circle cx="435" cy="110" r="9" fill="#eff6ff" stroke="#bfdbfe" stroke-width="1"/>
  <text x="435" y="113.5" text-anchor="middle" font-size="9.5" font-weight="700" fill="#2563eb">2</text>
  <rect x="398" y="88" width="74" height="15" fill="#ffffff"/>
  <text x="435" y="99" text-anchor="middle" font-size="9.5" font-weight="600" fill="#2563eb">ForwardAuth</text>

  <!-- (3) Traefik -> Frontend: 수직 하강! -->
  <path d="M 300 145 L 300 240" fill="none" stroke="#334155" stroke-width="1.3" marker-end="url(#arrow)"/>
  <circle cx="300" cy="165" r="9" fill="#f1f5f9" stroke="#cbd5e1" stroke-width="1"/>
  <text x="300" y="168.5" text-anchor="middle" font-size="9.5" font-weight="700" fill="#475569">3</text>
  <rect x="232" y="157" width="58" height="15" fill="#ffffff"/>
  <text x="261" y="168" text-anchor="middle" font-size="9" font-weight="600" fill="#475569">my-space.*</text>

  <!-- Traefik -> Backend 라우팅: 직각 꺾임선 (api.*) -->
  <path d="M 335 130 L 410 130 L 410 220 L 560 220 L 560 240" fill="none" stroke="#64748b" stroke-width="1.1" marker-end="url(#arrow)"/>
  <rect x="440" y="212" width="28" height="14" fill="#ffffff"/>
  <text x="454" y="222" text-anchor="middle" font-size="9" font-weight="600" fill="#64748b">api.*</text>

  <!-- (5) Backend -> Infra 연결선 (SQL, S3, Search) -->
  <!-- Backend -> PostgreSQL -->
  <path d="M 540 335 L 540 375 L 300 375 L 300 455" fill="none" stroke="#334155" stroke-width="1.3" marker-end="url(#arrow)"/>
  <circle cx="390" cy="375" r="9" fill="#f1f5f9" stroke="#cbd5e1" stroke-width="1"/>
  <text x="390" y="378.5" text-anchor="middle" font-size="9.5" font-weight="700" fill="#475569">5</text>
  <rect x="408" y="367" width="58" height="15" fill="#ffffff"/>
  <text x="437" y="378" text-anchor="middle" font-size="9.5" font-weight="600" fill="#475569">SQL Query</text>

  <!-- Backend -> MinIO S3 -->
  <path d="M 560 335 L 560 415 L 530 415 L 530 455" fill="none" stroke="#334155" stroke-width="1.3" marker-end="url(#arrow)"/>
  <rect x="540" y="407" width="40" height="14" fill="#ffffff"/>
  <text x="560" y="417" text-anchor="middle" font-size="9.5" font-weight="600" fill="#475569">S3 API</text>

  <!-- Backend -> OpenSearch -->
  <path d="M 580 335 L 580 375 L 750 375 L 750 455" fill="none" stroke="#334155" stroke-width="1.3" marker-end="url(#arrow)"/>
  <rect x="632" y="367" width="70" height="15" fill="#ffffff"/>
  <text x="667" y="378" text-anchor="middle" font-size="9.5" font-weight="600" fill="#475569">Search Index</text>

  <!-- (6) ArgoCD -> k3s Cluster: Auto-Sync 점선 화살표 -->
  <path d="M 915 455 L 878 455" fill="none" stroke="#059669" stroke-width="1.3" stroke-dasharray="4 3" marker-end="url(#arrow-green)"/>
  <rect x="828" y="442" width="52" height="24" fill="#ffffff"/>
  <text x="854" y="452" text-anchor="middle" font-size="9" font-weight="700" fill="#059669">GitOps</text>
  <text x="854" y="463" text-anchor="middle" font-size="8.5" fill="#059669">Auto-Sync</text>

</svg>

</body>
</html>
'''

output_html = "/Users/limkeunhyeok/workspace/homelab-infra/docs/dashed-blueprint.html"
with open(output_html, "w", encoding="utf-8") as f:
    f.write(html_content)

print("HTML updated with true factual specs.")
