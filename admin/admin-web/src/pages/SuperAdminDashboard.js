import React, { useEffect, useState } from "react";
import { db, auth } from "../firebase";
import { collection, getDocs, addDoc, deleteDoc, doc } from "firebase/firestore";
import { createUserWithEmailAndPassword, signOut } from "firebase/auth";

const SuperAdminDashboard = () => {
  const [activeTab, setActiveTab] = useState("dashboard");
  const [admins, setAdmins] = useState([]);
  const [loading, setLoading] = useState(true);
  const [newAdminEmail, setNewAdminEmail] = useState("");
  const [newAdminPassword, setNewAdminPassword] = useState("");
  const [newAdminCity, setNewAdminCity] = useState("Abbottabad");
  const [adding, setAdding] = useState(false);
  const [collapsed, setCollapsed] = useState(false);

  useEffect(() => {
    const fetchAdmins = async () => {
      setLoading(true);
      try {
        const snapshot = await getDocs(collection(db, "users"));
        const adminsData = snapshot.docs
          .map(doc => ({ id: doc.id, ...doc.data() }))
          .filter(user => user.role === "admin");
        setAdmins(adminsData);
      } catch (err) {
        console.error("Error fetching admins:", err);
      } finally {
        setLoading(false);
      }
    };
    fetchAdmins();
  }, []);

  // Collapse sidebar by default on mobile & tablet
  useEffect(() => {
    if (window.innerWidth < 1024) {
      setCollapsed(true);
    }
  }, []);

  const handleAddAdmin = async () => {
    if (!newAdminEmail || !newAdminPassword) return alert("Enter email & password!");
    setAdding(true);
    try {
      const userCredential = await createUserWithEmailAndPassword(auth, newAdminEmail, newAdminPassword);
      const uid = userCredential.user.uid;
      const docRef = await addDoc(collection(db, "users"), {
        email: newAdminEmail,
        role: "admin",
        uid,
        city: newAdminCity,
        cityId: newAdminCity.toLowerCase(),
        createdAt: new Date(),
      });

      setAdmins(prev => [
        ...prev,
        {
          id: docRef.id,
          email: newAdminEmail,
          role: "admin",
          uid,
          city: newAdminCity,
          cityId: newAdminCity.toLowerCase(),
        },
      ]);
      setNewAdminEmail("");
      setNewAdminPassword("");
      setNewAdminCity("Abbottabad");
      alert("Admin added successfully!");
    } catch (err) {
      alert(err.code === "auth/email-already-in-use" ? "Email already registered." : err.message);
    } finally {
      setAdding(false);
    }
  };

  const handleRemoveAdmin = async (id) => {
    if (!window.confirm("Are you sure you want to remove this admin?")) return;
    try {
      await deleteDoc(doc(db, "users", id));
      setAdmins(prev => prev.filter(admin => admin.id !== id));
      alert("Admin removed successfully");
    } catch (err) {
      console.error("Error removing admin:", err);
    }
  };

  const handleLogout = async () => {
    await signOut(auth);
    window.location.href = "/login";
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gradient-to-br from-violet-50 via-purple-50 to-fuchsia-100">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-purple-200 border-t-purple-600 rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-purple-600 font-semibold">Loading...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col md:flex-row min-h-screen bg-gradient-to-br from-violet-50 via-purple-50 to-fuchsia-100">
      
      {/* ---------------- SIDEBAR ---------------- */}
      <div className={`${collapsed ? "w-full md:w-20" : "w-full md:w-72"} bg-gradient-to-b from-violet-600 via-purple-600 to-fuchsia-600 shadow-2xl transition-all duration-300 relative flex-shrink-0`}>
        <div className="p-6">
          {/* Header */}
          <div className="flex items-center justify-between mb-10">
            {!collapsed && (
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 bg-white/20 backdrop-blur-sm rounded-xl flex items-center justify-center text-white font-bold text-xl shadow-lg">
                  <svg className="w-7 h-7" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                  </svg>
                </div>
                <div>
                  <h2 className="text-2xl font-bold text-white">SuperAdmin</h2>
                  <p className="text-xs text-purple-200">Master Control</p>
                </div>
              </div>
            )}
            {collapsed && (
              <div className="flex items-center gap-3 -mb-10 md:hidden">
              <div className="w-12 h-12 bg-white/20 backdrop-blur-sm rounded-xl flex items-center justify-center text-white font-bold text-xl shadow-lg">
                <svg className="w-7 h-7" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
              </div>
              <div>
                <h2 className="text-2xl font-bold text-white">SuperAdmin</h2>
                <p className="text-xs text-purple-200">Master Control</p>
              </div>
            </div>
            )}
          </div>

          <button 
            onClick={() => setCollapsed(!collapsed)}
            className="absolute top-6 right-4 w-8 h-8 bg-white/10 hover:bg-white/20 backdrop-blur-sm rounded-lg flex items-center justify-center text-white transition-all duration-300 hover:scale-110"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>

          {/* Navigation */}
          <nav className={`space-y-2 mt-8 ${collapsed ? "hidden" : ""}`}>
            <button
              onClick={() => setActiveTab("dashboard")}
              className={`w-full text-left px-4 py-3.5 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                activeTab === "dashboard" 
                  ? "bg-white text-purple-600 shadow-lg font-semibold transform scale-105" 
                  : "text-white hover:bg-white/10 hover:translate-x-1"
              }`}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-3zM14 12a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1v-7z" />
              </svg>
              {!collapsed && <span>Dashboard</span>}
            </button>

            <button
              onClick={() => setActiveTab("manageAdmins")}
              className={`w-full text-left px-4 py-3.5 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                activeTab === "manageAdmins" 
                  ? "bg-white text-purple-600 shadow-lg font-semibold transform scale-105" 
                  : "text-white hover:bg-white/10 hover:translate-x-1"
              }`}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
              </svg>
              {!collapsed && <span>Manage Admins</span>}
            </button>

            <button
              onClick={() => setActiveTab("payments")}
              className={`w-full text-left px-4 py-3.5 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                activeTab === "payments" 
                  ? "bg-white text-purple-600 shadow-lg font-semibold transform scale-105" 
                  : "text-white hover:bg-white/10 hover:translate-x-1"
              }`}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
              </svg>
              {!collapsed && <span>Payments</span>}
            </button>

            <div className="pt-4 mt-4 border-t border-white/20">
              <button
                onClick={handleLogout}
                className="w-full text-left px-4 py-3.5 rounded-xl text-white hover:bg-red-500/20 transition-all duration-300 flex items-center gap-3 hover:translate-x-1"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                </svg>
                {!collapsed && <span>Logout</span>}
              </button>
            </div>
          </nav>
        </div>
      </div>

      {/* ---------------- MAIN CONTENT ---------------- */}
      <div className="flex-1 w-full p-4 md:p-8 overflow-auto">

        {/* ---------------- DASHBOARD ---------------- */}
        {activeTab === "dashboard" && (
          <div className="space-y-8">
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <h2 className="text-4xl font-bold bg-gradient-to-r from-violet-600 to-fuchsia-600 bg-clip-text text-transparent">Dashboard Overview</h2>
                <p className="text-gray-600 mt-1">Monitor your system at a glance</p>
              </div>
              <div className="text-sm text-gray-500">
                {new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Card 1 - Total Admins */}
              <div className="bg-gradient-to-br from-violet-500 to-purple-600 p-8 rounded-2xl shadow-xl text-white transform transition duration-300 hover:scale-105 hover:shadow-2xl relative overflow-hidden">
                <div className="absolute top-0 right-0 w-32 h-32 bg-white/10 rounded-full -mr-16 -mt-16"></div>
                <div className="relative">
                  <div className="flex items-center justify-between mb-4">
                    <svg className="w-12 h-12 opacity-80" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
                    </svg>
                  </div>
                  <p className="text-purple-100 text-sm font-medium mb-2">Total Admins</p>
                  <h3 className="text-5xl font-bold mb-2">{admins.length}</h3>
                  <div className="flex items-center gap-1 text-sm text-purple-100">
                    <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                    </svg>
                    <span>Active administrators</span>
                  </div>
                </div>
              </div>

              {/* Card 2 - Pending Requests */}
              <div className="bg-gradient-to-br from-fuchsia-500 to-pink-600 p-8 rounded-2xl shadow-xl text-white transform transition duration-300 hover:scale-105 hover:shadow-2xl relative overflow-hidden">
                <div className="absolute top-0 right-0 w-32 h-32 bg-white/10 rounded-full -mr-16 -mt-16"></div>
                <div className="relative">
                  <div className="flex items-center justify-between mb-4">
                    <svg className="w-12 h-12 opacity-80" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </div>
                  <p className="text-pink-100 text-sm font-medium mb-2">Pending Requests</p>
                  <h3 className="text-5xl font-bold mb-2">0</h3>
                  <div className="flex items-center gap-1 text-sm text-pink-100">
                    <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clipRule="evenodd" />
                    </svg>
                    <span>Awaiting approval</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* ---------------- MANAGE ADMINS ---------------- */}
        {activeTab === "manageAdmins" && (
          <div className="space-y-6">
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <h2 className="text-4xl font-bold bg-gradient-to-r from-violet-600 to-purple-600 bg-clip-text text-transparent">Manage Admins</h2>
                <p className="text-gray-600 mt-1">Add and manage administrator accounts</p>
              </div>
              <div className="bg-white px-4 py-2 rounded-xl shadow-md">
                <span className="text-sm text-gray-600">Total: </span>
                <span className="font-bold text-purple-600 text-lg">{admins.length}</span>
              </div>
            </div>

            {/* Add Admin Form */}
            <div className="bg-white/80 backdrop-blur-lg p-6 rounded-2xl shadow-xl border border-white/20">
              <h3 className="text-xl font-semibold text-gray-800 mb-4 flex items-center gap-2">
                <svg className="w-6 h-6 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
                Add New Admin
              </h3>
              <div className="flex flex-col md:flex-row gap-4">
                <div className="flex-1">
                  <input
                    type="email"
                    placeholder="Admin email"
                    value={newAdminEmail}
                    onChange={(e) => setNewAdminEmail(e.target.value)}
                    className="w-full px-4 py-3 border border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-400 focus:border-transparent shadow-sm transition bg-white"
                  />
                </div>
                <div className="flex-1">
                  <input
                    type="password"
                    placeholder="Admin password"
                    value={newAdminPassword}
                    onChange={(e) => setNewAdminPassword(e.target.value)}
                    className="w-full px-4 py-3 border border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-400 focus:border-transparent shadow-sm transition bg-white"
                  />
                </div>
                <div className="flex-1">
                  <select
                    value={newAdminCity}
                    onChange={(e) => setNewAdminCity(e.target.value)}
                    className="w-full px-4 py-3 border border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-400 focus:border-transparent shadow-sm transition bg-white"
                  >
                    <option value="Abbottabad">Abbottabad</option>
                    <option value="Mansehra">Mansehra</option>
                    <option value="Rawalpindi">Rawalpindi</option>
                  </select>
                </div>
                <button
                  onClick={handleAddAdmin}
                  disabled={adding}
                  className={`px-6 py-3 rounded-xl text-white font-semibold transition-all duration-300 shadow-lg ${
                    adding 
                      ? "bg-gray-400 cursor-not-allowed" 
                      : "bg-gradient-to-r from-violet-500 to-purple-600 hover:from-violet-600 hover:to-purple-700 hover:shadow-xl transform hover:-translate-y-0.5"
                  }`}
                >
                  {adding ? (
                    <span className="flex items-center gap-2">
                      <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none"></circle>
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                      Adding...
                    </span>
                  ) : (
                    "Add Admin"
                  )}
                </button>
              </div>
            </div>

            {/* Admins Table */}
            <div className="bg-white shadow-2xl rounded-2xl border border-gray-100 overflow-x-auto">
              <table className="w-full min-w-[600px]">
                <thead className="bg-gradient-to-r from-violet-600 to-purple-600 text-white">
                  <tr>
                    <th className="py-4 px-6 text-left font-semibold">Email</th>
                    <th className="py-4 px-6 text-left font-semibold">Role</th>
                    <th className="py-4 px-6 text-left font-semibold">Action</th>
                  </tr>
                </thead>

                <tbody>
                  {admins.map((admin, index) => (
                    <tr key={admin.id} className={`border-b transition-colors hover:bg-purple-50 ${index % 2 === 0 ? 'bg-gray-50' : 'bg-white'}`}>
                      <td className="py-4 px-6">
                        <div className="flex items-center gap-3">
                          <div className="w-10 h-10 bg-gradient-to-br from-violet-400 to-purple-400 rounded-full flex items-center justify-center text-white font-semibold shadow-md">
                            {admin.email?.charAt(0).toUpperCase()}
                          </div>
                          <span className="font-medium text-gray-800">{admin.email}</span>
                        </div>
                      </td>
                      <td className="py-4 px-6">
                        <span className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-purple-100 text-purple-700 rounded-full text-sm font-semibold">
                          <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                            <path fillRule="evenodd" d="M2.166 4.999A11.954 11.954 0 0010 1.944 11.954 11.954 0 0017.834 5c.11.65.166 1.32.166 2.001 0 5.225-3.34 9.67-8 11.317C5.34 16.67 2 12.225 2 7c0-.682.057-1.35.166-2.001zm11.541 3.708a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                          </svg>
                          {admin.role}
                        </span>
                      </td>
                      <td className="py-4 px-6">
                        <button
                          onClick={() => handleRemoveAdmin(admin.id)}
                          className="inline-flex items-center gap-1.5 bg-gradient-to-r from-red-500 to-rose-600 text-white px-4 py-2 rounded-lg hover:from-red-600 hover:to-rose-700 transition-all duration-300 shadow-md hover:shadow-lg transform hover:-translate-y-0.5 font-medium"
                        >
                          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                          </svg>
                          Remove
                        </button>
                      </td>
                    </tr>
                  ))}
                  {admins.length === 0 && (
                    <tr>
                      <td colSpan="3" className="text-center py-12 text-gray-500">
                        <svg className="w-16 h-16 mx-auto mb-4 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
                        </svg>
                        <p className="text-lg font-medium">No admins found</p>
                        <p className="text-sm text-gray-400 mt-1">Add your first admin above</p>
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* ---------------- PAYMENTS ---------------- */}
        {activeTab === "payments" && (
          <div className="space-y-6">
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <h2 className="text-4xl font-bold bg-gradient-to-r from-violet-600 to-fuchsia-600 bg-clip-text text-transparent">Payments</h2>
                <p className="text-gray-600 mt-1">Manage payment transactions</p>
              </div>
            </div>

            <div className="bg-white/80 backdrop-blur-lg p-12 rounded-2xl shadow-xl border border-white/20 text-center">
              <div className="w-20 h-20 bg-gradient-to-br from-violet-100 to-purple-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <svg className="w-10 h-10 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
                </svg>
              </div>
              <h3 className="text-xl font-semibold text-gray-800 mb-2">Payment System</h3>
              <p className="text-gray-600">Payment related data will be implemented here.</p>
            </div>
          </div>
        )}

      </div>
    </div>
  );
};

export default SuperAdminDashboard;