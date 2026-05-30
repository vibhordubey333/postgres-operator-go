package postgres

import (
	"strings"
	"testing"

	postgresv1alpha1 "github.com/vibhordubey333/postgres-operator-go/api/v1alpha1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestBuildSecret(t *testing.T) {
	db := &postgresv1alpha1.PostgresDatabase{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "test-db",
			Namespace: "default",
		},
		Spec: postgresv1alpha1.PostgresDatabaseSpec{
			DatabaseName: "testdb",
		},
	}

	tests := []struct {
		name    string
		sslMode string
	}{
		{
			name:    "sslmode require",
			sslMode: "require",
		},
		{
			name:    "sslmode disable",
			sslMode: "disable",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			secret := BuildSecret(db, tt.sslMode)

			if secret.Name != "test-db-credentials" {
				t.Errorf("expected secret name test-db-credentials, got %s", secret.Name)
			}

			dsn := secret.StringData["DATABASE_URL"]
			expectedSuffix := "?sslmode=" + tt.sslMode
			if !strings.HasSuffix(dsn, expectedSuffix) {
				t.Errorf("expected DSN to end with %s, got %s", expectedSuffix, dsn)
			}
		})
	}
}
