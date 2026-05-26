const navItems = [
  ["dashboard", "لوحة التحكم"],
  ["projects", "المشاريع"],
  ["project-detail", "تفاصيل المشروع"],
  ["real-estate", "العقارات"],
  ["agriculture", "الزراعة"],
  ["livestock", "الثروة الحيوانية"],
  ["partners", "الشركاء"],
  ["finance", "المالية"],
  ["reports", "التقارير"],
  ["documents", "المستندات"],
  ["settings", "الإعدادات"],
  ["public-website", "الموقع العام"]
];
function renderNav(active) {
  const nav = document.getElementById("nav");
  nav.innerHTML = navItems.map(([key, label]) =>
    `<a href="./${key}.html" class="${key === active ? "active" : ""}">${label}</a>`
  ).join("");
}

