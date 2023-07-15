package controllers

import (
	"context"
	"fmt"
	"math"
	"reflect"
	"strings"
	"sync"
	"time"

	"github.com/sirupsen/logrus"
	v1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	//intstr "k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// NamespaceReconciler reconciles a Namespace object
type NamespaceReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

var (
	// projectNamespaces maps a project to its namespaces
	projectNamespaces = make(map[string]map[string]struct{})

	// namespaceToProjectMap maps a namespace to its project
	namespaceToProjectMap = make(map[string]string)

	lock = &sync.Mutex{}

	log = logrus.New()

	retryCount = make(map[string]int)
)

func (r *NamespaceReconciler) ensureKubeStateMetricsDeployment(ctx context.Context, projectId string, namespaces []string) error {
	app := "dyn-metrics"
	image := "rancher/mirrored-kube-state-metrics-kube-state-metrics:v2.6.0"
	deploymentName := app + "-for-" + projectId
	namespaceList := strings.Join(namespaces, ",")
	command := []string{
		"/kube-state-metrics",
		"--namespaces=" + namespaceList,
		"--port=8080",
		"--resources=certificatesigningrequests,configmaps,cronjobs,daemonsets,deployments,endpoints,horizontalpodautoscalers,ingresses,jobs,limitranges,mutatingwebhookconfigurations,namespaces,networkpolicies,nodes,persistentvolumeclaims,persistentvolumes,poddisruptionbudgets,pods,replicasets,replicationcontrollers,resourcequotas,secrets,services,statefulsets,storageclasses,validatingwebhookconfigurations,volumeattachments",
	}

	deployment := &v1.Deployment{}
	err := r.Get(ctx, client.ObjectKey{Namespace: "cattle-monitoring-system", Name: deploymentName}, deployment)

	// Define the desired state of the Deployment
	desiredDeployment := newKubeStateMetricsDeployment(deploymentName, app, projectId, command, image)

	switch {
	case err == nil:
		// Deployment exists. Update it if its spec has changed.
		if !reflect.DeepEqual(deployment.Spec, desiredDeployment.Spec) {
			deployment.Spec = desiredDeployment.Spec
			if err := r.Update(ctx, deployment); err != nil {
				log.Error(err, "Failed to update kube-state-metrics Deployment", "Deployment.Namespace", deployment.Namespace, "Deployment.Name", deployment.Name)
				return err
			}
			log.Info("Updated kube-state-metrics Deployment", "Deployment.Namespace", deployment.Namespace, "Deployment.Name", deployment.Name)
		}
	case errors.IsNotFound(err):
		// Deployment does not exist. Create a new one.
		deployment = desiredDeployment
		if err := r.Create(ctx, deployment); err != nil {
			log.Error(err, "Failed to create kube-state-metrics Deployment", "Deployment.Namespace", deployment.Namespace, "Deployment.Name", deployment.Name)
			return err
		}
		log.Info("Created kube-state-metrics Deployment", "Deployment.Namespace", deployment.Namespace, "Deployment.Name", deployment.Name)
	default:
		// Unexpected error.
		log.Error(err, "Failed to get kube-state-metrics Deployment", "Deployment.Namespace", "cattle-monitoring-system", "Deployment.Name", deployment.Name)
		return err
	}

	return nil
}

func newKubeStateMetricsDeployment(deploymentName string, app string, projectId string, command []string, image string) *v1.Deployment {
	return &v1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      deploymentName,
			Namespace: "cattle-monitoring-system", // replace with the namespace where you want to create the Deployment
		},
		Spec: v1.DeploymentSpec{
			Replicas: int32Ptr(1), // replace with the number of replicas you need
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{"project-app": deploymentName},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{"project-app": deploymentName, "app": app, "project_id": projectId},
				},
				Spec: corev1.PodSpec{
					ServiceAccountName: "rancher-monitoring-kube-state-metrics",
					Containers: []corev1.Container{
						{
							Name:    "kube-state-metrics",
							Image:   image, // replace with the version you need
							Command: command,
						},
					},
				},
			},
		},
	}
}

func int32Ptr(i int32) *int32 { return &i }

func (r *NamespaceReconciler) deleteKubeStateMetricsDeployment(ctx context.Context, projectId string) error {
	deploymentName := fmt.Sprintf("dyn-metrics-for-%s", projectId)

	// Delete the Deployment
	deployment := &v1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      deploymentName,
			Namespace: "cattle-monitoring-system",
		},
	}
	if err := r.Delete(ctx, deployment); client.IgnoreNotFound(err) != nil {
		log.Error(err, "Failed to delete Deployment", "Deployment", deploymentName)
		return err
	}

	// Delete the Service
	service := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      deploymentName,
			Namespace: "cattle-monitoring-system",
		},
	}
	if err := r.Delete(ctx, service); client.IgnoreNotFound(err) != nil {
		log.Error(err, "Failed to delete Service", "Service", deploymentName)
		return err
	}

	return nil
}

func getNamespaceListFromMap(namespaceMap map[string]struct{}) []string {
	namespaces := make([]string, len(namespaceMap))
	i := 0
	for namespace := range namespaceMap {
		namespaces[i] = namespace
		i++
	}
	return namespaces
}

// Reconcile compares the state specified by the Namespace object against the actual cluster state
// and performs operations to make the cluster state reflect the state specified by the user.

// Handle a namespace that has been deleted.
func (r *NamespaceReconciler) handleNamespaceDeleted(ctx context.Context, namespaceName string) error {
	lock.Lock()
	defer lock.Unlock()

	projectId := namespaceToProjectMap[namespaceName]
	delete(projectNamespaces[projectId], namespaceName)

	log.WithFields(logrus.Fields{
		"namespace": namespaceName,
		"projectId": projectId,
	}).Info("Deleting namespace for projectId")
	if len(projectNamespaces[projectId]) == 0 {
		log.WithFields(logrus.Fields{
			"projectId": projectId,
		}).Info("projectId has no more namespaces. Deleting entry")
		if err := r.deleteKubeStateMetricsDeployment(ctx, projectId); err != nil {
			return fmt.Errorf("failed to delete kube-state-metrics Deployment for projectId %s: %w", projectId, err)
		}
		delete(projectNamespaces, projectId)
	} else {
		namespaceList := getNamespaceListFromMap(projectNamespaces[projectId])
		if err := r.ensureKubeStateMetricsDeployment(ctx, projectId, namespaceList); err != nil {
			return fmt.Errorf("failed to update kube-state-metrics Deployment for projectId %s: %w", projectId, err)
		}
	}
	delete(namespaceToProjectMap, namespaceName)
	log.WithFields(logrus.Fields{
		"namespace": namespaceName,
		"projectId": projectId,
	}).Info("Namespace of projectId deleted OK")
	log.WithFields(logrus.Fields{
		"currentSetOfNamespaces": projectNamespaces,
	}).Info("Current set of namespaces")

	return nil
}

// Handle a namespace that has been created or updated.
func (r *NamespaceReconciler) handleNamespaceUpdated(ctx context.Context, namespace *corev1.Namespace) error {
	projectId, ok := namespace.Labels["field.cattle.io/projectId"]
	if !ok {
		log.WithFields(logrus.Fields{
			"namespace": namespace.Name,
		}).Warnf("No projectId label found for namespace")
		return nil
	}

	lock.Lock()
	defer lock.Unlock()

	if _, exists := projectNamespaces[projectId]; !exists {
		projectNamespaces[projectId] = make(map[string]struct{})
	}
	projectNamespaces[projectId][namespace.Name] = struct{}{}
	namespaceToProjectMap[namespace.Name] = projectId

	log.WithFields(logrus.Fields{
		"namespace": namespace.Name,
		"projectId": namespace.Labels["field.cattle.io/projectId"],
	}).Info("Updating namespace for projectId")
	namespaces := getNamespaceListFromMap(projectNamespaces[projectId])
	if err := r.ensureKubeStateMetricsDeployment(ctx, projectId, namespaces); err != nil {
		if errors.IsConflict(err) {
			log.WithFields(logrus.Fields{
				"namespace": namespace.Name,
				"projectId": projectId,
			}).Warnf("Temporary conflict when updating Deployment. Will be retried: %v", err)
			return nil
		} else {
			return fmt.Errorf("failed to ensure kube-state-metrics Deployment for projectId %s: %w", projectId, err)
		}
	}
	log.WithFields(logrus.Fields{
		"namespace": namespace.Name,
		"projectId": namespace.Labels["field.cattle.io/projectId"],
	}).Info("Namespace for projectId added/updated OK")
	log.WithFields(logrus.Fields{
		"currentSetOfNamespaces": projectNamespaces,
	}).Info("Current set of namespaces")

	return nil
}

func (r *NamespaceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	// Checking whether the context has been cancelled
	select {
	case <-ctx.Done():
		return ctrl.Result{}, ctx.Err()
	default:
	}

	namespace := &corev1.Namespace{}
	namespacename := req.NamespacedName.Name
	err := r.Get(ctx, req.NamespacedName, namespace)
	if err != nil {
		if errors.IsNotFound(err) {
			if err := r.handleNamespaceDeleted(ctx, namespacename); err != nil {
				return r.handleRetry(namespacename, err)
			}
			delete(retryCount, namespacename)
			log.WithFields(logrus.Fields{
				"namespace": namespacename,
				"projectId": namespaceToProjectMap[namespacename],
			}).Info("Namespace deleted from projectId")
			log.WithFields(logrus.Fields{
				"currentSetOfNamespaces": projectNamespaces,
			}).Info("Current set of namespaces")
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, fmt.Errorf("unable to fetch Namespace %s: %w", namespacename, err)
	}

	if err := r.handleNamespaceUpdated(ctx, namespace); err != nil {
		return r.handleRetry(namespacename, err)
	}
	delete(retryCount, namespacename)
	return ctrl.Result{}, nil
}

func (r *NamespaceReconciler) handleRetry(namespace string, err error) (ctrl.Result, error) {
	retries := retryCount[namespace]
	if retries >= 5 {
		log.Error("Failed to ensure kube-state-metrics Deployment for projectId, no more retries")
		delete(retryCount, namespace)
		return ctrl.Result{}, nil
	}
	delay := time.Duration(math.Pow(2, float64(retries))) * time.Second
	retryCount[namespace]++
	return ctrl.Result{RequeueAfter: delay}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *NamespaceReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&corev1.Namespace{}).
		Complete(r)
}
