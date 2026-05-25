package postgres

// labelsForDB returns the standard label set applied to all objects
// managed for a given PostgresDatabase instance.
func labelsForDB(name string) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":       "postgresql",
		"app.kubernetes.io/instance":   name,
		"app.kubernetes.io/managed-by": "postgres-operator-go",
	}
}

// int64Ptr returns a pointer to the given int64 value.
func int64Ptr(i int64) *int64 { return &i }

// boolPtr returns a pointer to the given bool value.
func boolPtr(b bool) *bool { return &b }
