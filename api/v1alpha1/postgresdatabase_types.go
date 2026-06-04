// Package v1alpha1 contains API Schema definitions for the postgres v1alpha1 API group
// +kubebuilder:object:generate=true
// +groupName=postgres.vibhordubey.com
package v1alpha1

import (
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// PostgresDatabaseSpec defines the desired state of PostgresDatabase.
type PostgresDatabaseSpec struct {
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	DatabaseName string `json:"databaseName"`

	// +kubebuilder:default="16.2"
	Version string `json:"version,omitempty"`

	// +kubebuilder:validation:Required
	Storage StorageSpec `json:"storage"`

	// +kubebuilder:default=1
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=5
	Replicas int32 `json:"replicas,omitempty"`

	Resources         ResourceSpec `json:"resources,omitempty"`
	BackupSchedule    string       `json:"backupSchedule,omitempty"`
	MaintenanceWindow string       `json:"maintenanceWindow,omitempty"`
}

type StorageSpec struct {
	// +kubebuilder:default="10Gi"
	Size resource.Quantity `json:"size"`
	// +kubebuilder:default="gp3"
	StorageClass string `json:"storageClass,omitempty"`
}

type ResourceSpec struct {
	// +kubebuilder:default="500m"
	CPURequest string `json:"cpuRequest,omitempty"`
	// +kubebuilder:default="1"
	CPULimit string `json:"cpuLimit,omitempty"`
	// +kubebuilder:default="512Mi"
	MemRequest string `json:"memRequest,omitempty"`
	// +kubebuilder:default="1Gi"
	MemLimit string `json:"memLimit,omitempty"`
}

type DatabasePhase string

const (
	PhaseProvisioning DatabasePhase = "Provisioning"
	PhaseReady        DatabasePhase = "Ready"
	PhaseFailed       DatabasePhase = "Failed"
	PhaseDeleting     DatabasePhase = "Deleting"
)

type PostgresDatabaseStatus struct {
	// +kubebuilder:validation:Enum=Provisioning;Ready;Failed;Deleting
	Phase               DatabasePhase      `json:"phase,omitempty"`
	Conditions          []metav1.Condition `json:"conditions,omitempty"`
	ConnectionSecretRef string             `json:"connectionSecretRef,omitempty"`
	ObservedGeneration  int64              `json:"observedGeneration,omitempty"`
	ReadyReplicas       int32              `json:"readyReplicas,omitempty"`
}

// PostgresDatabase is the Schema for the postgresdatabases API.
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Database",type=string,JSONPath=".spec.databaseName"
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=".status.readyReplicas"
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=".metadata.creationTimestamp"
type PostgresDatabase struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              PostgresDatabaseSpec   `json:"spec,omitempty"`
	Status            PostgresDatabaseStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type PostgresDatabaseList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []PostgresDatabase `json:"items"`
}

func init() {
	SchemeBuilder.Register(&PostgresDatabase{}, &PostgresDatabaseList{})
}
