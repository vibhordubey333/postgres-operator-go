package postgres

import (
	postgresv1alpha1 "github.com/vibhordubey333/postgres-operator-go/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func BuildStatefulSet(db *postgresv1alpha1.PostgresDatabase, secret *corev1.Secret) *appsv1.StatefulSet {
	labels := labelsForDB(db.Name)
	replicas := db.Spec.Replicas
	storageSize := db.Spec.Storage.Size
	storageClass := db.Spec.Storage.StorageClass
	image := "postgres:" + db.Spec.Version

	return &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{
			Name: db.Name, Namespace: db.Namespace, Labels: labels,
		},
		Spec: appsv1.StatefulSetSpec{
			Replicas:    &replicas,
			ServiceName: db.Name + "-headless",
			Selector:    &metav1.LabelSelector{MatchLabels: labels},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels},
				Spec: corev1.PodSpec{
					SecurityContext: &corev1.PodSecurityContext{
						RunAsUser:    int64Ptr(999),
						FSGroup:      int64Ptr(999),
						RunAsNonRoot: boolPtr(true),
					},
					Containers: []corev1.Container{{
						Name:  "postgres",
						Image: image,
						Ports: []corev1.ContainerPort{{ContainerPort: 5432, Name: "postgres"}},
						Env:   buildEnvVars(secret),
						Resources: corev1.ResourceRequirements{
							Requests: corev1.ResourceList{
								corev1.ResourceCPU:    resource.MustParse(db.Spec.Resources.CPURequest),
								corev1.ResourceMemory: resource.MustParse(db.Spec.Resources.MemRequest),
							},
							Limits: corev1.ResourceList{
								corev1.ResourceCPU:    resource.MustParse(db.Spec.Resources.CPULimit),
								corev1.ResourceMemory: resource.MustParse(db.Spec.Resources.MemLimit),
							},
						},
						LivenessProbe: &corev1.Probe{
							ProbeHandler: corev1.ProbeHandler{Exec: &corev1.ExecAction{
								Command: []string{"pg_isready", "-U", "$(POSTGRES_USER)"},
							}},
							InitialDelaySeconds: 30, PeriodSeconds: 10,
						},
						ReadinessProbe: &corev1.Probe{
							ProbeHandler: corev1.ProbeHandler{Exec: &corev1.ExecAction{
								Command: []string{"pg_isready", "-U", "$(POSTGRES_USER)"},
							}},
							InitialDelaySeconds: 5, PeriodSeconds: 5,
						},
						VolumeMounts: []corev1.VolumeMount{
							{Name: "data", MountPath: "/var/lib/postgresql/data"},
						},
						SecurityContext: &corev1.SecurityContext{
							AllowPrivilegeEscalation: boolPtr(false),
							Capabilities:             &corev1.Capabilities{Drop: []corev1.Capability{"ALL"}},
						},
					}},
				},
			},
			VolumeClaimTemplates: []corev1.PersistentVolumeClaim{{
				ObjectMeta: metav1.ObjectMeta{Name: "data"},
				Spec: corev1.PersistentVolumeClaimSpec{
					AccessModes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
					Resources: corev1.VolumeResourceRequirements{
						Requests: corev1.ResourceList{corev1.ResourceStorage: storageSize},
					},
					StorageClassName: &storageClass,
				},
			}},
		},
	}
}

func buildEnvVars(secret *corev1.Secret) []corev1.EnvVar {
	fromSecret := func(key string) corev1.EnvVar {
		return corev1.EnvVar{
			Name: key,
			ValueFrom: &corev1.EnvVarSource{SecretKeyRef: &corev1.SecretKeySelector{
				LocalObjectReference: corev1.LocalObjectReference{Name: secret.Name},
				Key:                  key,
			}},
		}
	}
	return []corev1.EnvVar{
		fromSecret("POSTGRES_USER"),
		fromSecret("POSTGRES_PASSWORD"),
		fromSecret("POSTGRES_DB"),
		{Name: "PGDATA", Value: "/var/lib/postgresql/data/pgdata"},
	}
}
