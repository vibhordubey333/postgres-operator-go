package controller

import (
	"context"
	"fmt"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	postgresv1alpha1 "github.com/vibhordubey333/postgres-operator-go/api/v1alpha1"
	"github.com/vibhordubey333/postgres-operator-go/pkg/postgres"
)

const (
	finalizerName  = "postgres.example.com/finalizer"
	requeueAfter   = 30 * time.Second
	conditionReady = "Ready"
)

type PostgresDatabaseReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=postgres.example.com,resources=postgresdatabases,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=postgres.example.com,resources=postgresdatabases/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=postgres.example.com,resources=postgresdatabases/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=statefulsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=services;persistentvolumeclaims;secrets,verbs=get;list;watch;create;update;patch;delete

func (r *PostgresDatabaseReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// 1. Fetch the resource; ignore if already gone
	db := &postgresv1alpha1.PostgresDatabase{}
	if err := r.Get(ctx, req.NamespacedName, db); err != nil {
		if errors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// 2. Handle deletion: run cleanup, then remove our finalizer
	if !db.DeletionTimestamp.IsZero() {
		return r.handleDeletion(ctx, db)
	}

	// 3. Register our finalizer so we can clean up on delete
	if !controllerutil.ContainsFinalizer(db, finalizerName) {
		controllerutil.AddFinalizer(db, finalizerName)
		if err := r.Update(ctx, db); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{Requeue: true}, nil
	}

	// 4. Mark as Provisioning only if not already progressing
	if db.Status.Phase == "" || db.Status.Phase == postgresv1alpha1.PhaseFailed {
		if err := r.setPhase(ctx, db, postgresv1alpha1.PhaseProvisioning); err != nil {
			return ctrl.Result{}, err
		}
	}

	// 5. Reconcile credentials Secret (create only if absent)
	secret, err := r.reconcileSecret(ctx, db)
	if err != nil {
		logger.Error(err, "failed to reconcile secret")
		return r.setFailed(ctx, db, err)
	}

	// 6. Reconcile StatefulSet (create-or-update, idempotent)
	if err := r.reconcileStatefulSet(ctx, db, secret); err != nil {
		logger.Error(err, "failed to reconcile statefulset")
		return r.setFailed(ctx, db, err)
	}

	// 7. Reconcile headless Service
	if err := r.reconcileService(ctx, db); err != nil {
		logger.Error(err, "failed to reconcile service")
		return r.setFailed(ctx, db, err)
	}

	// 8. Poll readiness; requeue until all replicas are ready
	ready, err := r.checkReadiness(ctx, db)
	if err != nil {
		return ctrl.Result{RequeueAfter: requeueAfter}, err
	}
	if !ready {
		logger.Info("not yet ready, requeuing", "name", db.Name)
		return ctrl.Result{RequeueAfter: requeueAfter}, nil
	}

	logger.Info("reconciled successfully", "name", db.Name)
	return r.setReady(ctx, db)
}

func (r *PostgresDatabaseReconciler) reconcileStatefulSet(
	ctx context.Context,
	db *postgresv1alpha1.PostgresDatabase,
	secret *corev1.Secret,
) error {
	desired := postgres.BuildStatefulSet(db, secret)
	if err := controllerutil.SetControllerReference(db, desired, r.Scheme); err != nil {
		return err
	}
	current := &appsv1.StatefulSet{}
	current.Name = desired.Name
	current.Namespace = desired.Namespace
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, current, func() error {
		current.Spec = desired.Spec
		return nil
	})
	return err
}

func (r *PostgresDatabaseReconciler) reconcileSecret(
	ctx context.Context,
	db *postgresv1alpha1.PostgresDatabase,
) (*corev1.Secret, error) {
	secret := &corev1.Secret{}
	name := client.ObjectKey{
		Name:      fmt.Sprintf("%s-credentials", db.Name),
		Namespace: db.Namespace,
	}
	err := r.Get(ctx, name, secret)
	if errors.IsNotFound(err) {
		secret = postgres.BuildSecret(db)
		if setErr := controllerutil.SetControllerReference(db, secret, r.Scheme); setErr != nil {
			return nil, setErr
		}
		return secret, r.Create(ctx, secret)
	}
	return secret, err
}

func (r *PostgresDatabaseReconciler) reconcileService(
	ctx context.Context,
	db *postgresv1alpha1.PostgresDatabase,
) error {
	desired := postgres.BuildService(db)
	if err := controllerutil.SetControllerReference(db, desired, r.Scheme); err != nil {
		return err
	}
	current := &corev1.Service{}
	current.Name = desired.Name
	current.Namespace = desired.Namespace
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, current, func() error {
		current.Spec.Ports = desired.Spec.Ports
		current.Spec.Selector = desired.Spec.Selector
		return nil
	})
	return err
}

func (r *PostgresDatabaseReconciler) checkReadiness(
	ctx context.Context,
	db *postgresv1alpha1.PostgresDatabase,
) (bool, error) {
	sts := &appsv1.StatefulSet{}
	key := client.ObjectKey{Name: db.Name, Namespace: db.Namespace}
	if err := r.Get(ctx, key, sts); err != nil {
		return false, err
	}
	db.Status.ReadyReplicas = sts.Status.ReadyReplicas
	return sts.Status.ReadyReplicas == db.Spec.Replicas, nil
}

func (r *PostgresDatabaseReconciler) handleDeletion(
	ctx context.Context,
	db *postgresv1alpha1.PostgresDatabase,
) (ctrl.Result, error) {
	if controllerutil.ContainsFinalizer(db, finalizerName) {
		// Place pre-delete hooks here (e.g., take a final backup)
		controllerutil.RemoveFinalizer(db, finalizerName)
		if err := r.Update(ctx, db); err != nil {
			return ctrl.Result{}, err
		}
	}
	return ctrl.Result{}, nil
}

// SetupWithManager registers the controller with the Manager.
func (r *PostgresDatabaseReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&postgresv1alpha1.PostgresDatabase{}).
		Owns(&appsv1.StatefulSet{}).
		Owns(&corev1.Service{}).
		Owns(&corev1.Secret{}).
		Complete(r)
}

func (r *PostgresDatabaseReconciler) setFailed(
	ctx context.Context,
	db *postgresv1alpha1.PostgresDatabase,
	reconcileErr error,
) (ctrl.Result, error) {
	db.Status.Phase = postgresv1alpha1.PhaseFailed
	meta.SetStatusCondition(&db.Status.Conditions, metav1.Condition{
		Type:               "Failed",
		Status:             metav1.ConditionTrue,
		ObservedGeneration: db.Generation,
		Reason:             "ReconcileError",
		Message:            reconcileErr.Error(),
	})
	return ctrl.Result{}, r.Status().Update(ctx, db)
}

// setReady marks the database as Ready and records the connection secret reference.
func (r *PostgresDatabaseReconciler) setReady(
	ctx context.Context,
	db *postgresv1alpha1.PostgresDatabase,
) (ctrl.Result, error) {
	db.Status.Phase = postgresv1alpha1.PhaseReady
	db.Status.ConnectionSecretRef = fmt.Sprintf("%s-credentials", db.Name)
	meta.SetStatusCondition(&db.Status.Conditions, metav1.Condition{
		Type:               "Ready",
		Status:             metav1.ConditionTrue,
		ObservedGeneration: db.Generation,
		Reason:             "Reconciled",
		Message:            "PostgresDatabase is ready",
	})
	return ctrl.Result{RequeueAfter: requeueAfter}, r.Status().Update(ctx, db)
}

// setPhase updates the status phase field.
func (r *PostgresDatabaseReconciler) setPhase(
	ctx context.Context,
	db *postgresv1alpha1.PostgresDatabase,
	phase postgresv1alpha1.DatabasePhase,
) error {
	db.Status.Phase = phase
	db.Status.ObservedGeneration = db.Generation
	return r.Status().Update(ctx, db)
}
