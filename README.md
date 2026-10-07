# cloud-guard

Mini CSPM con auto-remediación para detectar y corregir las fallas de configuración más comunes en la nube (buckets públicos, credenciales filtradas, permisos excesivos).

**Ciclo:** prevenir → detectar → responder.
**Entorno:** AWS emulado localmente con Floci (sin costo ni tarjeta).
**Uso ético:** solo en entornos propios y con datos falsos.

## Componentes

1. **Laboratorio vulnerable (Terraform):** bucket público, usuario IAM con permisos `*`, security group abierto a `0.0.0.0/0` en el puerto 22.
2. **Escáner (Python + boto3):** revisa buckets, IAM, claves y security groups. Genera reporte JSON/HTML con severidad y remediación, mapeado a CIS Benchmarks.
3. **Auto-remediación (Lambda + EventBridge):** ante un bucket público, activa *Block Public Access* y envía una alerta.
4. **Pipeline DevSecOps (GitHub Actions):** gitleaks (secretos) + Checkov/Trivy (Terraform). Falla ante hallazgos críticos.

## Demo en vivo

1. Se hace público un bucket.
2. La Lambda lo cierra y llega la alerta.
3. Se commitea una clave falsa y el pipeline se bloquea.
4. Se corre el escáner y se muestra el reporte antes y después.

## Casos reales que motivan el proyecto

Uber (2016, credenciales en GitHub), Alteryx (2017), LocalBlox, Prestige Software, JailCore, ESHYFT.

## Estructura del repo

```
cloud-guard/
├── terraform/
├── scanner/
├── remediation/
├── .github/workflows/
├── docs/
└── README.md
```

## Alcance por etapas

- **MVP:** Terraform + escáner de buckets e IAM + gitleaks.
- **Intermedio:** reporte HTML, más chequeos, auto-remediación.
- **Avanzado:** dashboard, consultas de CloudTrail, multicloud.

> Nota: verificar qué servicios de AWS cubre Floci (S3, IAM, Lambda, EventBridge, CloudTrail) antes de fijar el alcance.
