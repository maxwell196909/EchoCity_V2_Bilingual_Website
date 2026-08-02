const nav=document.querySelector(".main-nav");
const menuButton=document.querySelector(".menu-toggle");
const languageButton=document.querySelector(".language-switch");

if(menuButton&&nav){
  menuButton.addEventListener("click",()=>{
    const open=nav.classList.toggle("open");
    menuButton.setAttribute("aria-expanded",String(open));
  });
}

function setLanguage(lang){
  document.documentElement.dataset.lang=lang;
  document.documentElement.lang=lang==="zh"?"zh-CN":"en";
  document.querySelectorAll("[data-en][data-zh]").forEach(el=>el.textContent=el.dataset[lang]);
  document.querySelector(".lang-en")?.classList.toggle("active",lang==="en");
  document.querySelector(".lang-zh")?.classList.toggle("active",lang==="zh");
  localStorage.setItem("echocity-language",lang);
}

if(languageButton){
  languageButton.addEventListener("click",()=>{
    const current=document.documentElement.dataset.lang||"zh";
    setLanguage(current==="zh"?"en":"zh");
  });
  setLanguage(localStorage.getItem("echocity-language")||"zh");
}

const backgrounds=[...document.querySelectorAll(".hero-bg")];
let bgIndex=0;
if(backgrounds.length>1){
  setInterval(()=>{
    backgrounds[bgIndex].classList.remove("active");
    bgIndex=(bgIndex+1)%backgrounds.length;
    backgrounds[bgIndex].classList.add("active");
  },6000);
}

const observer=new IntersectionObserver(entries=>{
  entries.forEach(entry=>{if(entry.isIntersecting)entry.target.classList.add("visible")});
},{threshold:.15});
document.querySelectorAll(".reveal").forEach(el=>observer.observe(el));
const languageSwitch = document.getElementById("languageSwitch");
const contentZh = document.getElementById("contentZh");
const contentEn = document.getElementById("contentEn");
const languageLabel = document.getElementById("languageLabel");
const languageTarget = document.getElementById("languageTarget");
const wishInput = document.getElementById("wishInput");
const scrollText = document.getElementById("scrollText");

let currentLanguage = localStorage.getItem("echocityLanguage") || "zh";

function updateLanguage() {
  const isChinese = currentLanguage === "zh";

  contentZh.style.display = isChinese ? "block" : "none";
  contentEn.style.display = isChinese ? "none" : "block";

  languageLabel.textContent = isChinese ? "中文" : "EN";
  languageTarget.textContent = isChinese ? "EN" : "中文";

  wishInput.placeholder = isChinese
    ? "你好，我能帮你什么？"
    : "Hello, how can I help you?";

  scrollText.textContent = isChinese
    ? "向下滚动"
    : "Scroll down";

  document.documentElement.lang = isChinese ? "zh-CN" : "en";

  localStorage.setItem("echocityLanguage", currentLanguage);
}

languageSwitch.addEventListener("click", function () {
  currentLanguage = currentLanguage === "zh" ? "en" : "zh";
  updateLanguage();
});

updateLanguage();const openFormButton =
  document.getElementById("openFormButton");

if (openFormButton) {
  openFormButton.addEventListener("click", () => {
    window.location.href = "activity-create.html";
  });
}
