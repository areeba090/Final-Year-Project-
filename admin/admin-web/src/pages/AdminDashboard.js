import React, { useEffect, useRef, useState } from "react";
import { db, auth } from "../firebase";
import {
  collection,
  query,
  where,
  onSnapshot,
  updateDoc,
  deleteDoc,
  doc,
  addDoc,
  getDoc,
  setDoc,
} from "firebase/firestore";
import { signOut } from "firebase/auth";
import DeleteConfirmModal from "../components/DeleteConfirmModal";
import AddSchoolMapModal from "../components/AddSchoolMapModal";
import AddRouteModal from "../components/AddRouteModal";
import { useToast } from "../contexts/ToastContext";

const AdminDashboard = () => {
  const { success, error } = useToast();
  const [activeTab, setActiveTab] = useState("dashboard");
  const [collapsed, setCollapsed] = useState(false);
  const [deleteModal, setDeleteModal] = useState({ open: false, type: null, id: null, name: null });
  const [deleting, setDeleting] = useState(false);

  const [drivers, setDrivers] = useState([]);
  const [parents, setParents] = useState([]);
  const [routes, setRoutes] = useState([]);
  const [schools, setSchools] = useState([]);

  const [selectedDriver, setSelectedDriver] = useState(null);
  const [selectedParent, setSelectedParent] = useState(null);
  const [parentChildren, setParentChildren] = useState([]);

  const [adminProfile, setAdminProfile] = useState({
    name: "",
    phone: "",
    cnic: "",
    city: "Abbottabad",
  });

  const [allDriverRequests, setAllDriverRequests] = useState([]);
  const [savingProfile, setSavingProfile] = useState(false);
  const [addingRoute, setAddingRoute] = useState(false);
  const [addingSchool, setAddingSchool] = useState(false);
  const [addSchoolMapOpen, setAddSchoolMapOpen] = useState(false);
  const [addRouteModalOpen, setAddRouteModalOpen] = useState(false);

  // Live driver location for map
  const [selectedDriverLocation, setSelectedDriverLocation] = useState(null);
  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markerRef = useRef(null);

  // Collapse sidebar by default on mobile & tablet
  useEffect(() => {
    if (window.innerWidth < 1024) {
      setCollapsed(true);
    }
  }, []);

  // Subscribe to live location for selected driver
  useEffect(() => {
    if (!selectedDriver) {
      setSelectedDriverLocation(null);
      // Modal map container unmounts on close, so force a clean map instance
      // to avoid binding the next driver's map to a stale DOM node.
      mapInstanceRef.current = null;
      markerRef.current = null;
      return;
    }

    // Switching driver while modal is open should also recreate map + marker.
    mapInstanceRef.current = null;
    markerRef.current = null;

    const locRef = doc(db, "driverLocations", selectedDriver.id);
    const unsub = onSnapshot(locRef, (snap) => {
      if (!snap.exists()) {
        setSelectedDriverLocation(null);
        return;
      }
      const data = snap.data();
      if (typeof data.latitude === "number" && typeof data.longitude === "number") {
        setSelectedDriverLocation({
          lat: data.latitude,
          lng: data.longitude,
          updatedAt: data.timestamp,
        });
      } else {
        setSelectedDriverLocation(null);
      }
    });

    return () => unsub();
  }, [selectedDriver]);

  // Initialize/update Google Map when location changes
  useEffect(() => {
    if (!selectedDriverLocation || !window.google || !mapRef.current) return;

    const { lat, lng } = selectedDriverLocation;
    const position = { lat, lng };

    if (!mapInstanceRef.current) {
      mapInstanceRef.current = new window.google.maps.Map(mapRef.current, {
        center: position,
        zoom: 16,
        disableDefaultUI: false,
      });
      markerRef.current = new window.google.maps.Marker({
        position,
        map: mapInstanceRef.current,
        title: selectedDriver?.name || "Driver",
      });
    } else {
      markerRef.current.setPosition(position);
      mapInstanceRef.current.panTo(position);
    }
  }, [selectedDriverLocation, selectedDriver]);

  // Fetch admin profile
  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged(async (user) => {
      if (user) {
        const adminRef = doc(db, "users", user.uid);
        const snap = await getDoc(adminRef);
        if (snap.exists()) setAdminProfile(snap.data());
      }
    });
    return () => unsubscribe();
  }, []);

  const saveAdminProfile = async () => {
    const user = auth.currentUser;
    if (!user) return;
    const phone = adminProfile.phone || "";
    // Expect Pakistani mobile like +92 3XX XXXXXXX
    if (!/^\+923\d{9}$/.test(phone)) {
      error("Please enter a valid Pakistani mobile number (e.g. +92 3XX XXXXXXX).");
      return;
    }
    setSavingProfile(true);
    try {
      const adminRef = doc(db, "users", user.uid);
      // Use setDoc with merge so the profile can be created if it doesn't exist yet
      await setDoc(adminRef, adminProfile, { merge: true });
      success("Profile saved!");
    } catch (e) {
      error("Failed to save profile.");
    } finally {
      setSavingProfile(false);
    }
  };

  useEffect(() => {
    const q = query(collection(db, "users"), where("role", "==", "driver"));
    const unsub = onSnapshot(q, (snapshot) => {
      setDrivers(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const q = query(collection(db, "users"), where("role", "==", "parent"));
    const unsub = onSnapshot(q, (snapshot) => {
      setParents(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const unsub = onSnapshot(collection(db, "routes"), (snapshot) => {
      setRoutes(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const unsub = onSnapshot(collection(db, "schools"), (snapshot) => {
      setSchools(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const unsub = onSnapshot(collection(db, "requests"), (snapshot) => {
      setAllDriverRequests(
        snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
      );
    });
    return () => unsub();
  }, []);

  const approveDriver = async (id) => {
    const driverRef = doc(db, "users", id);
    const driverSnap = await getDoc(driverRef);
    const driverData = driverSnap.data();
    if (!driverData.route || !driverData.school) {
      error("Assign route and school before approving.");
      return;
    }
    try {
      await updateDoc(driverRef, {
        status: "active",
        assignedSeats: 0,
        availableSeats: driverData.seats || 0,
      });
      success("Driver approved.");
    } catch (e) {
      error("Failed to approve driver.");
    }
  };

  const rejectDriver = async (id) => {
    try {
      await updateDoc(doc(db, "users", id), { status: "rejected" });
      success("Driver rejected.");
    } catch (e) {
      error("Failed to reject driver.");
    }
  };

  const openDeleteModal = (type, id, name) => {
    setDeleteModal({ open: true, type, id, name });
  };

  const handleConfirmDelete = async () => {
    if (!deleteModal.id || !deleteModal.type) return;
    setDeleting(true);
    try {
      if (deleteModal.type === "driver" || deleteModal.type === "parent") {
        await deleteDoc(doc(db, "users", deleteModal.id));
      } else if (deleteModal.type === "route") {
        await deleteDoc(doc(db, "routes", deleteModal.id));
      } else if (deleteModal.type === "school") {
        await deleteDoc(doc(db, "schools", deleteModal.id));
      }
      success(
        deleteModal.type === "driver"
          ? "Driver removed."
          : deleteModal.type === "parent"
            ? "Parent removed."
            : deleteModal.type === "route"
              ? "Route deleted."
              : "School deleted."
      );
      setDeleteModal({ open: false, type: null, id: null, name: null });
    } catch (e) {
      error("Failed to delete. Please try again.");
    } finally {
      setDeleting(false);
    }
  };

  const removeDriver = (id, name) => {
    openDeleteModal("driver", id, name || "this driver");
  };

  const removeParent = (id, name) => {
    openDeleteModal("parent", id, name || "this parent");
  };

  const fetchChildren = (parent) => {
    const children = parent.children || [];
    setParentChildren(children.map((c, index) => ({ id: index, ...c })));
  };

  const addRouteFromModal = async (routeData) => {
    setAddingRoute(true);
    try {
      const name = `${routeData.schoolName} → ${routeData.destinationName}`;
      await addDoc(collection(db, "routes"), {
        name,
        schoolName: routeData.schoolName,
        schoolLatitude: routeData.schoolLatitude,
        schoolLongitude: routeData.schoolLongitude,
        ...(routeData.schoolId && { schoolId: routeData.schoolId }),
        destinationName: routeData.destinationName,
        destinationLatitude: routeData.destinationLatitude,
        destinationLongitude: routeData.destinationLongitude,
        ...(routeData.destinationAddress && { destinationAddress: routeData.destinationAddress }),
      });
      success("Route added with school and destination.");
      setAddRouteModalOpen(false);
    } catch (e) {
      error("Failed to add route.");
    } finally {
      setAddingRoute(false);
    }
  };

  const deleteRoute = (id, name) => {
    openDeleteModal("route", id, name || "this route");
  };

  const addSchoolFromMap = async (school) => {
    setAddingSchool(true);
    try {
      await addDoc(collection(db, "schools"), {
        name: school.name,
        latitude: school.latitude,
        longitude: school.longitude,
        ...(school.address && { address: school.address }),
      });
      success("School added with location.");
      setAddSchoolMapOpen(false);
    } catch (e) {
      error("Failed to add school.");
    } finally {
      setAddingSchool(false);
    }
  };

  const deleteSchool = (id, name) => {
    openDeleteModal("school", id, name || "this school");
  };

  const logout = async () => {
    await signOut(auth);
    window.location.href = "/";
  };

  const assignDriverToChild = async (parent, childIndex, driverId) => {
    const parentRef = doc(db, "users", parent.id);
    const driverRef = doc(db, "users", driverId);
    const updatedChildren = parent.children.map((c, index) =>
      index === childIndex ? { ...c, assignedDriver: driverId } : c,
    );
    await updateDoc(parentRef, { children: updatedChildren });
    const driverSnap = await getDoc(driverRef);
    const driverData = driverSnap.data();
    await updateDoc(driverRef, {
      assignedSeats: (driverData.assignedSeats || 0) + 1,
      availableSeats: (driverData.availableSeats ?? driverData.seats ?? 0) - 1,
    });
    await addDoc(collection(db, "requests"), {
      parentId: parent.id,
      parentName: parent.name || "Unknown Parent",
      driverId,
      childIds: [updatedChildren[childIndex].name],
      status: "approved",
      createdAt: new Date(),
    });
    success("Driver assigned. They will see this child in their app.");
    fetchChildren({ ...parent, children: updatedChildren });
  };

  const approveRequest = async (req) => {
    try {
      const parentRef = doc(db, "users", req.parentId);
      const parentSnap = await getDoc(parentRef);
      const parentData = parentSnap.data();
      const updatedChildren = (parentData.children || []).map((child) =>
        req.childIds?.includes(child.name)
          ? { ...child, assignedDriver: req.driverId }
          : child,
      );
      await updateDoc(doc(db, "requests", req.id), { status: "approved" });
      await updateDoc(parentRef, { children: updatedChildren });
      success("Request approved.");
    } catch (e) {
      error("Failed to approve request.");
    }
  };

  const rejectRequest = async (reqId) => {
    try {
      await updateDoc(doc(db, "requests", reqId), { status: "rejected" });
      success("Request rejected.");
    } catch (e) {
      error("Failed to reject request.");
    }
  };

  const pendingDrivers = drivers.filter((d) =>
    d.status === "pending" || d.status === "inactive"
  );
  const verifiedDrivers = drivers.filter((d) => d.status === "active");
  const pendingRequests = allDriverRequests.filter(
    (r) => r.status === "pending",
  );

  const navItems = [
    {
      id: "dashboard",
      label: "Dashboard",
      icon: "M4 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-3zM14 12a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1v-7z",
    },
    {
      id: "profile",
      label: "Profile",
      icon: "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z",
    },
    {
      id: "drivers",
      label: "Drivers",
      icon: "M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2",
    },
    {
      id: "parents",
      label: "Parents",
      icon: "M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z",
    },
    {
      id: "routes",
      label: "Routes & Schools",
      icon: "M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7",
    },
    {
      id: "payments",
      label: "Payments",
      icon: "M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z",
    },
    {
      id: "earnings",
      label: "Earnings",
      icon: "M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
    },
  ];

  return (
    <div className="flex flex-col md:flex-row min-h-screen bg-gradient-to-br from-slate-50 via-emerald-50/30 to-teal-50">
      {/* Sidebar */}
      <aside
        className={`${collapsed ? "w-full md:w-20" : "w-full md:w-72"} bg-gradient-to-b from-emerald-600 via-teal-600 to-cyan-700 shadow-2xl transition-all duration-300 relative flex-shrink-0`}
      >
        <div className="p-6">
          <div className="flex items-center justify-between mb-10">
            {!collapsed && (
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 bg-white/20 backdrop-blur-sm rounded-xl flex items-center justify-center text-white shadow-lg">
                  <svg
                    className="w-7 h-7"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
                    />
                  </svg>
                </div>
                <div>
                  <h2 className="text-xl font-bold text-white">Admin Panel</h2>
                  <p className="text-xs text-emerald-200">
                    Transport Management
                  </p>
                </div>
              </div>
            )}
            {collapsed && (
              <div className="flex items-center gap-3 -mb-10 md:hidden">
                <div className="w-12 h-12 bg-white/20 backdrop-blur-sm rounded-xl flex items-center justify-center text-white shadow-lg">
                  <svg
                    className="w-7 h-7"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
                    />
                  </svg>
                </div>
                <div>
                  <h2 className="text-xl font-bold text-white">Admin Panel</h2>
                  <p className="text-xs text-emerald-200">
                    Transport Management
                  </p>
                </div>
              </div>
            )}
          </div>

          <button
            onClick={() => setCollapsed(!collapsed)}
            className="absolute top-6 right-4 w-8 h-8 bg-white/10 hover:bg-white/20 rounded-lg flex items-center justify-center text-white transition-all hover:scale-110"
          >
            <svg
              className="w-5 h-5"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M4 6h16M4 12h16M4 18h16"
              />
            </svg>
          </button>

          {!collapsed && (
            <div className="pt-2 pb-4 border-b border-white/20">
              <p className="text-emerald-100 text-sm font-medium truncate">
                {adminProfile.name || "Admin"}
              </p>
              <p className="text-emerald-200/80 text-xs truncate">
                {adminProfile.phone || "—"}
              </p>
            </div>
          )}

          <nav className={`space-y-1.5 mt-6 ${collapsed ? "hidden" : ""}`}>
            {navItems.map((item) => (
              <button
                key={item.id}
                onClick={() => setActiveTab(item.id)}
                className={`w-full text-left px-4 py-3 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                  activeTab === item.id
                    ? "bg-white text-emerald-700 shadow-lg font-semibold"
                    : "text-white hover:bg-white/10 hover:translate-x-1"
                }`}
              >
                <svg
                  className="w-5 h-5 flex-shrink-0"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d={item.icon}
                  />
                </svg>
                {!collapsed && <span>{item.label}</span>}
              </button>
            ))}

            <div className="pt-4 mt-4 border-t border-white/20">
              <button
                onClick={logout}
                className="w-full text-left px-4 py-3 rounded-xl text-white hover:bg-red-500/30 transition-all flex items-center gap-3 hover:translate-x-1"
              >
                <svg
                  className="w-5 h-5"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
                  />
                </svg>
                {!collapsed && <span>Logout</span>}
              </button>
            </div>
          </nav>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 p-6 lg:p-8 overflow-auto">
        {/* ——— Dashboard ——— */}
        {activeTab === "dashboard" && (
          <div className="space-y-8">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div>
                <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                  Dashboard
                </h1>
                <p className="text-slate-600 mt-1">
                  Overview of your transport operations
                </p>
              </div>
              <p className="text-sm text-slate-500">
                {new Date().toLocaleDateString("en-US", {
                  weekday: "long",
                  year: "numeric",
                  month: "long",
                  day: "numeric",
                })}
              </p>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100 hover:shadow-xl transition-shadow">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-slate-500 text-sm font-medium">
                      Total Drivers
                    </p>
                    <p className="text-3xl font-bold text-slate-800 mt-1">
                      {drivers.length}
                    </p>
                  </div>
                  <div className="w-14 h-14 bg-emerald-100 rounded-2xl flex items-center justify-center">
                    <svg
                      className="w-8 h-8 text-emerald-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth="2"
                        d="M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2"
                      />
                    </svg>
                  </div>
                </div>
              </div>

              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100 hover:shadow-xl transition-shadow">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-slate-500 text-sm font-medium">
                      Total Parents
                    </p>
                    <p className="text-3xl font-bold text-slate-800 mt-1">
                      {parents.length}
                    </p>
                  </div>
                  <div className="w-14 h-14 bg-teal-100 rounded-2xl flex items-center justify-center">
                    <svg
                      className="w-8 h-8 text-teal-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth="2"
                        d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"
                      />
                    </svg>
                  </div>
                </div>
              </div>

              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100 hover:shadow-xl transition-shadow">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-slate-500 text-sm font-medium">
                      Pending Drivers
                    </p>
                    <p className="text-3xl font-bold text-amber-600 mt-1">
                      {pendingDrivers.length}
                    </p>
                  </div>
                  <div className="w-14 h-14 bg-amber-100 rounded-2xl flex items-center justify-center">
                    <svg
                      className="w-8 h-8 text-amber-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth="2"
                        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                  </div>
                </div>
              </div>

              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100 hover:shadow-xl transition-shadow">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-slate-500 text-sm font-medium">
                      Pending Requests
                    </p>
                    <p className="text-3xl font-bold text-cyan-600 mt-1">
                      {pendingRequests.length}
                    </p>
                  </div>
                  <div className="w-14 h-14 bg-cyan-100 rounded-2xl flex items-center justify-center">
                    <svg
                      className="w-8 h-8 text-cyan-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth="2"
                        d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
                      />
                    </svg>
                  </div>
                </div>
              </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100">
                <h3 className="text-lg font-semibold text-slate-800 mb-4">
                  Quick stats
                </h3>
                <ul className="space-y-3">
                  <li className="flex justify-between items-center py-2 border-b border-slate-100">
                    <span className="text-slate-600">Verified drivers</span>
                    <span className="font-semibold text-emerald-600">
                      {verifiedDrivers.length}
                    </span>
                  </li>
                  <li className="flex justify-between items-center py-2 border-b border-slate-100">
                    <span className="text-slate-600">Routes</span>
                    <span className="font-semibold text-slate-800">
                      {routes.length}
                    </span>
                  </li>
                  <li className="flex justify-between items-center py-2">
                    <span className="text-slate-600">Schools</span>
                    <span className="font-semibold text-slate-800">
                      {schools.length}
                    </span>
                  </li>
                </ul>
              </div>
              <div className="bg-gradient-to-br from-emerald-500 to-teal-600 rounded-2xl p-6 shadow-lg text-white">
                <h3 className="text-lg font-semibold mb-2">Need to act</h3>
                <p className="text-emerald-100 text-sm mb-4">
                  {pendingDrivers.length > 0 || pendingRequests.length > 0
                    ? `You have ${pendingDrivers.length} driver(s) and ${pendingRequests.length} request(s) waiting for approval.`
                    : "All caught up. No pending approvals."}
                </p>
                {(pendingDrivers.length > 0 || pendingRequests.length > 0) && (
                  <button
                    onClick={() =>
                      setActiveTab(
                        pendingDrivers.length > 0 ? "drivers" : "parents",
                      )
                    }
                    className="px-4 py-2 bg-white text-emerald-700 rounded-xl font-medium hover:bg-emerald-50 transition"
                  >
                    Go to approvals
                  </button>
                )}
              </div>
            </div>
          </div>
        )}

        {/* ——— Profile ——— */}
        {activeTab === "profile" && (
          <div className="space-y-6 max-w-2xl">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Profile
              </h1>
              <p className="text-slate-600 mt-1">Update your admin details</p>
            </div>

            <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100 space-y-5">
              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">
                  Name
                </label>
                <input
                  value={adminProfile.name}
                  onChange={(e) =>
                    setAdminProfile({ ...adminProfile, name: e.target.value })
                  }
                  className="w-full px-4 py-3 border border-slate-200 rounded-xl focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400 transition"
                  placeholder="Your name"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">
                  Phone (Pakistan)
                </label>
                <div className="flex">
                  <span className="inline-flex items-center gap-1 px-3 py-3 rounded-l-xl border border-r-0 border-slate-200 bg-slate-50 text-sm text-slate-700">
                    <span role="img" aria-label="Pakistan flag">
                      🇵🇰
                    </span>
                    +92
                  </span>
                  <input
                    value={(adminProfile.phone || "").replace(/^\+92/, "")}
                    onChange={(e) => {
                      const digits = e.target.value.replace(/\D/g, "").slice(0, 10);
                      setAdminProfile({
                        ...adminProfile,
                        phone: digits ? `+92${digits}` : "",
                      });
                    }}
                    className="w-full px-4 py-3 border border-slate-200 border-l-0 rounded-r-xl focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400 transition"
                    placeholder="3XX XXXXXXX"
                    inputMode="numeric"
                  />
                </div>
                <p className="mt-1 text-xs text-slate-500">
                  Enter a valid Pakistani mobile number, e.g. 3XX XXXXXXX.
                </p>
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">
                  CNIC
                </label>
                <input
                  value={adminProfile.cnic}
                  onChange={(e) =>
                    setAdminProfile({ ...adminProfile, cnic: e.target.value })
                  }
                  className="w-full px-4 py-3 border border-slate-200 rounded-xl focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400 transition"
                  placeholder="CNIC"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">
                  City
                </label>
                <select
                  value={adminProfile.city}
                  onChange={(e) =>
                    setAdminProfile({ ...adminProfile, city: e.target.value })
                  }
                  className="w-full px-4 py-3 border border-slate-200 rounded-xl focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400 transition bg-white"
                >
                  <option>Abbottabad</option>
                  <option>Mansehra</option>
                  <option>Rawalpindi</option>
                </select>
              </div>
              <button
                onClick={saveAdminProfile}
                disabled={savingProfile}
                className="px-6 py-3 bg-gradient-to-r from-emerald-500 to-teal-600 text-white rounded-xl font-semibold shadow-lg hover:shadow-xl transition disabled:opacity-70"
              >
                {savingProfile ? "Saving…" : "Save profile"}
              </button>
            </div>
          </div>
        )}

        {/* ——— Drivers ——— */}
        {activeTab === "drivers" && (
          <div className="space-y-8">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Drivers
              </h1>
              <p className="text-slate-600 mt-1">Approve and manage drivers</p>
            </div>

            <section>
              <h2 className="text-xl font-semibold text-slate-800 mb-4 flex items-center gap-2">
                <span className="w-8 h-8 bg-amber-100 rounded-lg flex items-center justify-center">
                  <svg
                    className="w-4 h-4 text-amber-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                </span>
                Pending approval ({pendingDrivers.length})
              </h2>
              {pendingDrivers.length === 0 ? (
                <div className="bg-slate-50 rounded-2xl p-8 text-center text-slate-500">
                  No pending drivers. New registrations will appear here.
                </div>
              ) : (
                <div className="grid gap-4">
                  {pendingDrivers.map((driver) => (
                    <div
                      key={driver.id}
                      className="bg-white rounded-2xl p-4 sm:p-5 shadow-md border border-slate-100 flex flex-col gap-4 min-w-0 overflow-hidden"
                    >
                      <div className="flex items-center gap-3 min-w-0">
                        <div className="w-10 h-10 sm:w-12 sm:h-12 flex-shrink-0 bg-emerald-100 rounded-xl flex items-center justify-center text-emerald-700 font-bold text-lg">
                          {(driver.name || "D")[0]}
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="font-semibold text-slate-800 truncate">
                            {driver.name || "—"}
                          </p>
                          <p className="text-sm text-slate-500 truncate">
                            {driver.phone || driver.email}
                          </p>
                        </div>
                      </div>
                      <div className="flex flex-col sm:flex-row sm:flex-wrap gap-3 border-t border-slate-100 pt-4 sm:pt-0 sm:border-t-0">
                        <div className="flex flex-col sm:flex-row gap-2 min-w-0">
                          <select
                            value={driver.route || ""}
                            onChange={async (e) => {
                              await updateDoc(doc(db, "users", driver.id), {
                                route: e.target.value,
                              });
                            }}
                            className="w-full min-w-0 sm:w-40 px-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-emerald-400 bg-white"
                          >
                            <option value="">Route</option>
                            {routes.map((r) => (
                              <option key={r.id} value={r.name}>
                                {r.name}
                              </option>
                            ))}
                          </select>
                          <select
                            value={driver.school || ""}
                            onChange={async (e) => {
                              await updateDoc(doc(db, "users", driver.id), {
                                school: e.target.value,
                              });
                            }}
                            className="w-full min-w-0 sm:w-40 px-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-emerald-400 bg-white"
                          >
                            <option value="">School</option>
                            {schools.map((s) => (
                              <option key={s.id} value={s.name}>
                                {s.name}
                              </option>
                            ))}
                          </select>
                        </div>
                        <div className="flex gap-2 flex-shrink-0">
                          <button
                            onClick={() => approveDriver(driver.id)}
                            className="flex-1 sm:flex-none px-4 py-2 bg-emerald-500 text-white rounded-lg font-medium hover:bg-emerald-600 transition text-sm whitespace-nowrap"
                          >
                            Approve
                          </button>
                          <button
                            onClick={() => rejectDriver(driver.id)}
                            className="flex-1 sm:flex-none px-4 py-2 bg-red-500 text-white rounded-lg font-medium hover:bg-red-600 transition text-sm whitespace-nowrap"
                          >
                            Reject
                          </button>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </section>

            <section>
              <h2 className="text-xl font-semibold text-slate-800 mb-4 flex items-center gap-2">
                <span className="w-8 h-8 bg-emerald-100 rounded-lg flex items-center justify-center">
                  <svg
                    className="w-4 h-4 text-emerald-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                </span>
                Verified drivers ({verifiedDrivers.length})
              </h2>
              {verifiedDrivers.length === 0 ? (
                <div className="bg-slate-50 rounded-2xl p-8 text-center text-slate-500">
                  No verified drivers yet.
                </div>
              ) : (
                <div className="grid gap-4">
                  {verifiedDrivers.map((driver) => (
                    <div
                      key={driver.id}
                      className="bg-white rounded-2xl p-5 shadow-md border border-slate-100 flex flex-wrap items-center justify-between gap-4"
                    >
                      <div className="flex items-center gap-4">
                        <div className="w-12 h-12 bg-teal-100 rounded-xl flex items-center justify-center text-teal-700 font-bold text-lg">
                          {(driver.name || "D")[0]}
                        </div>
                        <div>
                          <p className="font-semibold text-slate-800">
                            {driver.name || "—"}
                          </p>
                          <p className="text-sm text-slate-500">
                            {driver.route} · {driver.school}
                          </p>
                          <p className="text-xs text-slate-400">
                            Seats: {driver.assignedSeats || 0} /{" "}
                            {driver.availableSeats +
                              (driver.assignedSeats || 0) || driver.seats}
                          </p>
                        </div>
                      </div>
                      <div className="flex gap-2">
                        <button
                          onClick={() => setSelectedDriver(driver)}
                          className="px-4 py-2 bg-slate-100 text-slate-700 rounded-lg font-medium hover:bg-slate-200 transition"
                        >
                          Details
                        </button>
                        <button
                          onClick={() => removeDriver(driver.id, driver.name)}
                          className="px-4 py-2 bg-red-50 text-red-600 rounded-lg font-medium hover:bg-red-100 transition"
                        >
                          Remove
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </section>

            {selectedDriver && (
              <div
                className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
                onClick={() => setSelectedDriver(null)}
              >
                <div
                  className="bg-white rounded-2xl p-6 max-w-md w-full shadow-2xl max-h-[90vh] flex flex-col"
                  onClick={(e) => e.stopPropagation()}
                >
                  <h3 className="text-xl font-semibold text-slate-800 mb-4">
                    Driver details
                  </h3>
                  <div className="flex-1 overflow-y-auto pr-1 space-y-4">
                    <dl className="space-y-2 text-sm">
                    <div>
                      <dt className="text-slate-500">Name</dt>
                      <dd className="font-medium">{selectedDriver.name}</dd>
                    </div>
                    <div>
                      <dt className="text-slate-500">Phone</dt>
                      <dd className="font-medium">{selectedDriver.phone}</dd>
                    </div>
                    <div>
                      <dt className="text-slate-500">Vehicle</dt>
                      <dd className="font-medium">
                        {selectedDriver.vehicleName || "—"}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-slate-500">Route</dt>
                      <dd className="font-medium">{selectedDriver.route}</dd>
                    </div>
                    <div>
                      <dt className="text-slate-500">School</dt>
                      <dd className="font-medium">{selectedDriver.school}</dd>
                    </div>
                    <div>
                      <dt className="text-slate-500">Seats</dt>
                      <dd className="font-medium">
                        {selectedDriver.assignedSeats || 0} assigned,{" "}
                        {selectedDriver.availableSeats ?? 0} available
                      </dd>
                    </div>
                    </dl>
                    {(selectedDriver.profilePic ||
                    selectedDriver.cnicPic ||
                    selectedDriver.licensePic ||
                    selectedDriver.vehiclePic) && (
                      <div className="mt-2 space-y-3">
                        <h4 className="text-sm font-semibold text-slate-700">
                          Documents & photos
                        </h4>
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                          {selectedDriver.profilePic && (
                            <div className="border border-slate-200 rounded-xl overflow-hidden bg-slate-50">
                              <div className="px-3 py-2 text-xs font-medium text-slate-600">
                                Profile photo
                              </div>
                              <a
                                href={selectedDriver.profilePic}
                                target="_blank"
                                rel="noreferrer"
                              >
                                <img
                                  src={selectedDriver.profilePic}
                                  alt="Driver profile"
                                  className="w-full h-32 object-cover"
                                />
                              </a>
                            </div>
                          )}
                          {selectedDriver.cnicPic && (
                            <div className="border border-slate-200 rounded-xl overflow-hidden bg-slate-50">
                              <div className="px-3 py-2 text-xs font-medium text-slate-600">
                                CNIC
                              </div>
                              <a
                                href={selectedDriver.cnicPic}
                                target="_blank"
                                rel="noreferrer"
                              >
                                <img
                                  src={selectedDriver.cnicPic}
                                  alt="Driver CNIC"
                                  className="w-full h-32 object-cover"
                                />
                              </a>
                            </div>
                          )}
                          {selectedDriver.licensePic && (
                            <div className="border border-slate-200 rounded-xl overflow-hidden bg-slate-50">
                              <div className="px-3 py-2 text-xs font-medium text-slate-600">
                                License
                              </div>
                              <a
                                href={selectedDriver.licensePic}
                                target="_blank"
                                rel="noreferrer"
                              >
                                <img
                                  src={selectedDriver.licensePic}
                                  alt="Driver license"
                                  className="w-full h-32 object-cover"
                                />
                              </a>
                            </div>
                          )}
                          {selectedDriver.vehiclePic && (
                            <div className="border border-slate-200 rounded-xl overflow-hidden bg-slate-50">
                              <div className="px-3 py-2 text-xs font-medium text-slate-600">
                                Vehicle
                              </div>
                              <a
                                href={selectedDriver.vehiclePic}
                                target="_blank"
                                rel="noreferrer"
                              >
                                <img
                                  src={selectedDriver.vehiclePic}
                                  alt="Driver vehicle"
                                  className="w-full h-32 object-cover"
                                />
                              </a>
                            </div>
                          )}
                        </div>
                      </div>
                    )}
                    <div className="mt-2">
                      <h4 className="text-sm font-semibold text-slate-700 mb-2">
                        Live location
                      </h4>
                      {selectedDriverLocation ? (
                        <>
                          <div className="text-xs text-slate-500 mb-2">
                            Lat: {selectedDriverLocation.lat.toFixed(5)}, Lng:{" "}
                            {selectedDriverLocation.lng.toFixed(5)}
                          </div>
                          <div
                            ref={mapRef}
                            className="w-full h-64 rounded-xl border border-slate-200 overflow-hidden"
                          />
                        </>
                      ) : (
                        <p className="text-xs text-slate-500">
                          Waiting for driver GPS updates. Make sure the driver has started a ride in the app.
                        </p>
                      )}
                    </div>
                  </div>

                  <button
                    onClick={() => setSelectedDriver(null)}
                    className="mt-6 w-full py-2 bg-slate-100 text-slate-700 rounded-xl font-medium hover:bg-slate-200 transition"
                  >
                    Close
                  </button>
                </div>
              </div>
            )}
          </div>
        )}

        {/* ——— Parents ——— */}
        {activeTab === "parents" && (
          <div className="space-y-8">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Parents & children
              </h1>
              <p className="text-slate-600 mt-1">
                Manage parents and assign drivers to children
              </p>
            </div>

            {/* Pending requests first */}
            {pendingRequests.length > 0 && (
              <section>
                <h2 className="text-xl font-semibold text-slate-800 mb-4">
                  Parent driver requests
                </h2>
                <div className="space-y-3">
                  {pendingRequests.map((req) => (
                    <div
                      key={req.id}
                      className="bg-amber-50 border border-amber-200 rounded-2xl p-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 min-w-0 overflow-hidden"
                    >
                      <div className="min-w-0 flex-1">
                        <p className="font-medium text-slate-800 truncate">
                          {req.parentName}
                        </p>
                        <p className="text-sm text-slate-600 break-words mt-0.5">
                          Driver:{" "}
                          {drivers.find((d) => d.id === req.driverId)?.name ||
                            "—"}{" "}
                          · Children: {req.childIds?.join(", ")}
                        </p>
                      </div>
                      <div className="flex gap-2 flex-shrink-0">
                        <button
                          onClick={() => approveRequest(req)}
                          className="flex-1 sm:flex-none px-4 py-2 bg-emerald-500 text-white rounded-lg font-medium hover:bg-emerald-600 transition text-sm whitespace-nowrap"
                        >
                          Approve
                        </button>
                        <button
                          onClick={() => rejectRequest(req.id)}
                          className="flex-1 sm:flex-none px-4 py-2 bg-red-500 text-white rounded-lg font-medium hover:bg-red-600 transition text-sm whitespace-nowrap"
                        >
                          Reject
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </section>
            )}

            <section>
              <h2 className="text-xl font-semibold text-slate-800 mb-4">
                All parents
              </h2>
              {parents.length === 0 ? (
                <div className="bg-slate-50 rounded-2xl p-8 text-center text-slate-500">
                  No parents yet.
                </div>
              ) : (
                <div className="grid gap-4">
                  {parents.map((parent) => (
                    <div
                      key={parent.id}
                      className="bg-white rounded-2xl border border-slate-100 shadow-md overflow-hidden"
                    >
                      <div className="p-5 flex flex-wrap items-center justify-between gap-4">
                        <div className="flex items-center gap-4">
                          <div className="w-12 h-12 bg-teal-100 rounded-xl flex items-center justify-center text-teal-700 font-bold text-lg">
                            {(parent.name || "P")[0]}
                          </div>
                          <div>
                            <p className="font-semibold text-slate-800">
                              {parent.name || "—"}
                            </p>
                            <p className="text-sm text-slate-500">
                              {parent.phone}
                            </p>
                          </div>
                        </div>
                        <div className="flex gap-2">
                          <button
                            onClick={() => {
                              setSelectedParent(parent);
                              fetchChildren(parent);
                            }}
                            className="px-4 py-2 bg-emerald-500 text-white rounded-lg font-medium hover:bg-emerald-600 transition"
                          >
                            Children & assign driver
                          </button>
                          <button
                            onClick={() => removeParent(parent.id, parent.name)}
                            className="px-4 py-2 bg-red-50 text-red-600 rounded-lg font-medium hover:bg-red-100 transition"
                          >
                            Remove
                          </button>
                        </div>
                      </div>

                      {selectedParent?.id === parent.id && (
                        <div className="border-t border-slate-100 bg-slate-50/50 p-5">
                          <h4 className="font-medium text-slate-700 mb-3">
                            {parent.name}'s children
                          </h4>
                          {parentChildren.length === 0 ? (
                            <p className="text-slate-500 text-sm">
                              No children added.
                            </p>
                          ) : (
                            <div className="space-y-3">
                              {parentChildren.map((child, index) => (
                                <div
                                  key={child.id}
                                  className="flex flex-wrap items-center justify-between gap-3 bg-white rounded-xl p-3 border border-slate-100"
                                >
                                  <div>
                                    <p className="font-medium text-slate-800">
                                      {child.name}
                                    </p>
                                    <p className="text-sm text-slate-500">
                                      {child.school} · Driver:{" "}
                                      {child.assignedDriver
                                        ? verifiedDrivers.find(
                                            (d) =>
                                              d.id === child.assignedDriver,
                                          )?.name || "—"
                                        : "None"}
                                    </p>
                                  </div>
                                  <select
                                    value={child.assignedDriver || ""}
                                    onChange={(e) =>
                                      assignDriverToChild(
                                        selectedParent,
                                        index,
                                        e.target.value,
                                      )
                                    }
                                    className="px-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-emerald-400"
                                  >
                                    <option value="">Select driver</option>
                                    {verifiedDrivers.map((d) => (
                                      <option key={d.id} value={d.id}>
                                        {d.name}
                                      </option>
                                    ))}
                                  </select>
                                </div>
                              ))}
                            </div>
                          )}
                          <button
                            onClick={() => setSelectedParent(null)}
                            className="mt-4 text-sm text-slate-500 hover:text-slate-700"
                          >
                            Close
                          </button>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </section>
          </div>
        )}

        {/* ——— Routes & Schools ——— */}
        {activeTab === "routes" && (
          <div className="space-y-8">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Routes & schools
              </h1>
              <p className="text-slate-600 mt-1">
                Add and manage routes and schools
              </p>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100">
                <h3 className="text-lg font-semibold text-slate-800 mb-4">
                  Routes
                </h3>
                <div className="mb-4">
                  <button
                    type="button"
                    onClick={() => setAddRouteModalOpen(true)}
                    className="w-full sm:w-auto px-5 py-3 bg-emerald-500 text-white rounded-xl font-medium hover:bg-emerald-600 transition flex items-center justify-center gap-2"
                  >
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                    </svg>
                    Add route (school → destination)
                  </button>
                </div>
                <ul className="space-y-2">
                  {routes.map((r) => (
                    <li
                      key={r.id}
                      className="flex items-center justify-between py-2 px-3 rounded-lg hover:bg-slate-50 gap-2"
                    >
                      <div className="min-w-0 flex-1">
                        <span className="font-medium text-slate-800 block truncate">
                          {r.name}
                        </span>
                        {(r.schoolName != null || r.destinationName != null) && (
                          <div className="text-xs text-slate-500 mt-0.5 space-y-0.5">
                            {r.schoolName != null && (
                              <span className="block truncate">
                                School: {r.schoolName}
                                {r.schoolLatitude != null && ` (${r.schoolLatitude.toFixed(4)}, ${r.schoolLongitude.toFixed(4)})`}
                              </span>
                            )}
                            {r.destinationName != null && (
                              <span className="block truncate">
                                Destination: {r.destinationName}
                                {r.destinationLatitude != null && ` (${r.destinationLatitude.toFixed(4)}, ${r.destinationLongitude.toFixed(4)})`}
                              </span>
                            )}
                          </div>
                        )}
                      </div>
                      <button
                        onClick={() => deleteRoute(r.id, r.name)}
                        className="text-red-500 hover:text-red-700 text-sm font-medium flex-shrink-0"
                      >
                        Delete
                      </button>
                    </li>
                  ))}
                  {routes.length === 0 && (
                    <li className="text-slate-500 text-sm py-2">
                      No routes yet. Add a route by selecting a school and destination.
                    </li>
                  )}
                </ul>
              </div>

              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100">
                <h3 className="text-lg font-semibold text-slate-800 mb-4">
                  Schools
                </h3>
                <div className="mb-4">
                  <button
                    type="button"
                    onClick={() => setAddSchoolMapOpen(true)}
                    className="w-full sm:w-auto px-5 py-3 bg-emerald-500 text-white rounded-xl font-medium hover:bg-emerald-600 transition flex items-center justify-center gap-2"
                  >
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                    </svg>
                    Add school from map
                  </button>
                </div>
                <ul className="space-y-2">
                  {schools.map((s) => (
                    <li
                      key={s.id}
                      className="flex items-center justify-between py-2 px-3 rounded-lg hover:bg-slate-50 gap-2"
                    >
                      <div className="min-w-0 flex-1">
                        <span className="font-medium text-slate-800 block truncate">
                          {s.name}
                        </span>
                        {(s.latitude != null && s.longitude != null) && (
                          <span className="text-xs text-slate-500">
                            {s.latitude.toFixed(5)}, {s.longitude.toFixed(5)}
                          </span>
                        )}
                      </div>
                      <button
                        onClick={() => deleteSchool(s.id, s.name)}
                        className="text-red-500 hover:text-red-700 text-sm font-medium flex-shrink-0"
                      >
                        Delete
                      </button>
                    </li>
                  ))}
                  {schools.length === 0 && (
                    <li className="text-slate-500 text-sm py-2">
                      No schools yet. Add a school from map above.
                    </li>
                  )}
                </ul>
              </div>
            </div>
          </div>
        )}

        {/* ——— Payments ——— */}
        {activeTab === "payments" && (
          <div className="space-y-6">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Payments
              </h1>
              <p className="text-slate-600 mt-1">Manage parent payments</p>
            </div>
            <div className="bg-white rounded-2xl p-8 shadow-lg border border-slate-100">
              <div className="flex flex-col items-center justify-center text-center py-8">
                <div className="w-16 h-16 bg-emerald-100 rounded-2xl flex items-center justify-center mb-4">
                  <svg
                    className="w-8 h-8 text-emerald-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z"
                    />
                  </svg>
                </div>
                <p className="text-slate-600 mb-4">
                  Payment list and “Mark paid” can be wired to your payments
                  collection here.
                </p>
                <div className="w-full max-w-2xl overflow-x-auto">
                  <table className="w-full text-left text-sm">
                    <thead>
                      <tr className="border-b border-slate-200">
                        <th className="py-3 font-semibold text-slate-700">
                          Parent
                        </th>
                        <th className="py-3 font-semibold text-slate-700">
                          Status
                        </th>
                        <th className="py-3 font-semibold text-slate-700">
                          Action
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      {parents.slice(0, 5).map((p) => (
                        <tr key={p.id} className="border-b border-slate-100">
                          <td className="py-3">{p.name || "—"}</td>
                          <td className="py-3">
                            {p.paymentStatus || "Pending"}
                          </td>
                          <td className="py-3">
                            <button className="text-emerald-600 font-medium hover:underline">
                              Mark paid
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* ——— Earnings ——— */}
        {activeTab === "earnings" && (
          <div className="space-y-6">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Earnings
              </h1>
              <p className="text-slate-600 mt-1">
                View earnings from payments collection
              </p>
            </div>
            <div className="bg-white rounded-2xl p-8 shadow-lg border border-slate-100 text-center">
              <div className="w-16 h-16 bg-cyan-100 rounded-2xl flex items-center justify-center mx-auto mb-4">
                <svg
                  className="w-8 h-8 text-cyan-600"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
              </div>
              <p className="text-slate-600">
                Total earnings can be calculated from your payments collection
                when integrated.
              </p>
            </div>
          </div>
        )}
      </main>

      <AddSchoolMapModal
        isOpen={addSchoolMapOpen}
        onClose={() => setAddSchoolMapOpen(false)}
        onSelectSchool={addSchoolFromMap}
        isAdding={addingSchool}
      />

      <AddRouteModal
        isOpen={addRouteModalOpen}
        onClose={() => setAddRouteModalOpen(false)}
        onAddRoute={addRouteFromModal}
        schools={schools}
        isAdding={addingRoute}
      />

      <DeleteConfirmModal
        isOpen={deleteModal.open}
        onClose={() => !deleting && setDeleteModal({ open: false, type: null, id: null, name: null })}
        onConfirm={handleConfirmDelete}
        title={
          deleteModal.type === "driver"
            ? "Remove driver"
            : deleteModal.type === "parent"
              ? "Remove parent"
              : deleteModal.type === "route"
                ? "Delete route"
                : deleteModal.type === "school"
                  ? "Delete school"
                  : "Delete"
        }
        description="This action cannot be undone."
        itemName={deleteModal.name}
        confirmLabel="Delete"
        isLoading={deleting}
      />
    </div>
  );
};

export default AdminDashboard;
