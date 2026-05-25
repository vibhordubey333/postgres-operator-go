package postgres

import (
	postgresv1alpha1 "github.com/vibhordubey333/postgres-operator-go/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
)

// BuildService creates a headless Service so each pod gets a stable DNS entry:
// {pod-name}.{db-name}-headless.{namespace}.svc.cluster.local
func BuildService(db *postgresv1alpha1.PostgresDatabase) *corev1.Service {
	labels := labelsForDB(db.Name)
	return &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name: db.Name + "-headless", Namespace: db.Namespace, Labels: labels,
		},
		Spec: corev1.ServiceSpec{
			ClusterIP:                "None",
			PublishNotReadyAddresses: true,
			Selector:                 labels,
			Ports: []corev1.ServicePort{{
				Name:       "postgres",
				Port:       5432,
				TargetPort: intstr.FromString("postgres"),
				Protocol:   corev1.ProtocolTCP,
			}},
		},
	}
}
