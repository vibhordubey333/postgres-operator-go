package postgres

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"

	postgresv1alpha1 "github.com/vibhordubey333/postgres-operator-go/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// BuildSecret generates a Kubernetes Secret with random credentials.
// Called only when the Secret does not already exist — idempotent by design.
func BuildSecret(db *postgresv1alpha1.PostgresDatabase, sslMode string) *corev1.Secret {
	password := generatePassword(32)
	username := db.Spec.DatabaseName + "_user"
	dsn := fmt.Sprintf(
		"postgresql://%s:%s@%s-headless:5432/%s?sslmode=%s",
		username, password, db.Name, db.Spec.DatabaseName, sslMode,
	)
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      fmt.Sprintf("%s-credentials", db.Name),
			Namespace: db.Namespace,
			Labels:    labelsForDB(db.Name),
		},
		Type: corev1.SecretTypeOpaque,
		StringData: map[string]string{
			"POSTGRES_USER":     username,
			"POSTGRES_PASSWORD": password,
			"POSTGRES_DB":       db.Spec.DatabaseName,
			"DATABASE_URL":      dsn,
		},
	}
}

func generatePassword(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}
