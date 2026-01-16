/// H3 Event Relevance Detection Module
///
/// This module provides Uber H3-based spatial indexing for intelligent
/// event relevance detection in routing applications.
///
/// Key Components:
/// - [H3EventRelevanceDetector] - Core service for checking event-to-route relevance
/// - [H3MockEventDataset] - Fake dataset with timer-based event triggering
/// - [H3ReroutingController] - High-level controller for H3-aware rerouting
///
/// Usage:
/// ```dart
/// // Initialize
/// final h3Service = H3Service();
/// await h3Service.initialize();
///
/// final controller = H3ReroutingController(h3Service);
///
/// // Set route
/// controller.setRoute(routePath, origin, destination);
///
/// // Listen for reroute requests
/// controller.addRerouteListener((request) {
///   // Only called when event is H3-relevant to route
///   // Implement rerouting logic here
/// });
///
/// // Schedule mock event (triggers after 10 seconds by default)
/// await controller.scheduleMockEvent();
/// ```
///
/// The system ensures:
/// - Events are only considered if their H3 cell matches or is adjacent to route cells
/// - Events with no H3 overlap are IGNORED (no rerouting triggered)
/// - Rerouted paths avoid all event-affected H3 cells

export 'h3_event_relevance_detector.dart';
export 'h3_mock_event_dataset.dart';
export 'h3_rerouting_controller.dart';
