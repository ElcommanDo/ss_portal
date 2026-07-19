/* ==========================================================================
   SMART SYSTEM — MAIN.JS
   Vanilla JS: content rendering from data + site interactions.
   No external libraries.
   ========================================================================== */
(function(){
  "use strict";

  /* ---------------------------------------------------------------------
     ICONS — small inline SVG path library reused across cards
     --------------------------------------------------------------------- */
  const ICON = {
    cloud:'<path d="M17.5 19H9a5 5 0 1 1 1.3-9.8 6 6 0 0 1 11.2 3A4.5 4.5 0 0 1 20.5 19h-3"/>',
    shield:'<path d="M12 2l8 4v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6l8-4z"/>',
    network:'<circle cx="5" cy="6" r="2"/><circle cx="19" cy="6" r="2"/><circle cx="12" cy="18" r="2"/><path d="M5 8v3a2 2 0 0 0 2 2h2M19 8v3a2 2 0 0 0-2 2h-2M12 16v-3"/>',
    server:'<rect x="3" y="4" width="18" height="6" rx="1"/><rect x="3" y="14" width="18" height="6" rx="1"/><circle cx="7" cy="7" r=".5"/><circle cx="7" cy="17" r=".5"/>',
    backup:'<path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 3v6h-6"/>',
    chat:'<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
    bolt:'<path d="M13 2 4 14h6l-1 8 9-12h-6l1-8z"/>',
    ai:'<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>',
    erp:'<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    crm:'<circle cx="9" cy="8" r="3"/><path d="M2 20c0-3.3 3.1-6 7-6s7 2.7 7 6"/><circle cx="18" cy="8" r="2.2"/><path d="M16 14.2c2.7.4 4.5 2.5 4.5 5.8"/>',
    globe:'<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18 14 14 0 0 1 0-18z"/>',
    dt:'<path d="M4 12a8 8 0 1 1 8 8"/><path d="M4 12h4M4 12l3-3M4 12l3 3"/>',
    mobile:'<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>',
    web:'<circle cx="12" cy="12" r="9"/><path d="M3 9h18M3 15h18M12 3c2.5 2.5 3.5 5.5 3.5 9s-1 6.5-3.5 9c-2.5-2.5-3.5-5.5-3.5-9s1-6.5 3.5-9z"/>',
    iot:'<circle cx="12" cy="12" r="2.5"/><circle cx="12" cy="12" r="7" stroke-dasharray="2 3"/><path d="M12 2v3M12 19v3"/>',
    voip:'<path d="M4 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L14 13l5 2v4a2 2 0 0 1-2.2 2A16 16 0 0 1 2 6.2 2 2 0 0 1 4 4z"/>',
    consult:'<path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>',
    bi:'<path d="M4 20V10M11 20V4M18 20v-7"/>',
    check:'<path d="M20 6 9 17l-5-5"/>',
    support:'<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3.5"/><path d="M4.9 4.9l4 4M19.1 4.9l-4 4M4.9 19.1l4-4M19.1 19.1l-4-4"/>',
    award:'<circle cx="12" cy="8" r="5"/><path d="M8.5 13 7 22l5-3 5 3-1.5-9"/>',
    engineer:'<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 3.6-6 8-6s8 2 8 6"/>',
    innovation:'<path d="M9 18h6M10 22h4M12 2a6 6 0 0 0-3 11.2c.6.4 1 1 1 1.8h4c0-.8.4-1.4 1-1.8A6 6 0 0 0 12 2z"/>',
    health:'<path d="M20.8 8.6a5 5 0 0 0-8.3-3.7L12 5.4l-.5-.5A5 5 0 1 0 4.2 12l7 7a1.1 1.1 0 0 0 1.6 0l7-7a5 5 0 0 0 1-3.4z"/>',
    edu:'<path d="M2 9l10-5 10 5-10 5-10-5z"/><path d="M6 11v5c0 1.7 2.7 3 6 3s6-1.3 6-3v-5"/>',
    gov:'<path d="M3 10l9-6 9 6M4 10v9M20 10v9M9 19v-6h6v6M2 19h20"/>',
    bank:'<path d="M3 10l9-6 9 6M4 10v9h16v-9M2 19h20M8 13v3M12 13v3M16 13v3"/>',
    oil:'<path d="M12 2v6M8 8h8l2 4v10H6V12l2-4z"/>',
    retail:'<path d="M6 8h12l-1 12H7L6 8zM9 8V6a3 3 0 0 1 6 0v2"/>',
    factory:'<path d="M3 21V10l5 3V10l5 3V8l6 4v9H3z"/>',
    build:'<path d="M2 21h20M4 21V10l5-3v14M13 21V6l5-3v18M9 14h0M9 17h0M17 10h0M17 13h0M17 16h0"/>',
    telecom:'<path d="M4 15a8 8 0 0 1 16 0M7.5 12.5a4 4 0 0 1 9 0M12 22v-6"/>',
    logistics:'<rect x="1" y="7" width="15" height="10" rx="1"/><path d="M16 10h4l3 3v4h-7z"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>',
    energy:'<path d="M13 2 4 14h6l-1 8 9-12h-6l1-8z"/>',
    hotel:'<path d="M3 21V8l9-5 9 5v13M9 21v-6h6v6"/>',
    linkedin:'<path d="M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-4 0v7h-4v-7a6 6 0 0 1 6-6z"/><rect x="2" y="9" width="4" height="12"/><circle cx="4" cy="4" r="2"/>',
    mail:'<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 6-10 7L2 6"/>',
    phone:'<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3 19.5 19.5 0 0 1-6-6 19.8 19.8 0 0 1-3-8.7A2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1 1 .3 2 .7 3a2 2 0 0 1-.5 2.1L8 10a16 16 0 0 0 6 6l1.2-1.3a2 2 0 0 1 2.1-.5c1 .4 2 .6 3 .7a2 2 0 0 1 1.7 2z"/>',
    pin:'<path d="M12 22s7-6.3 7-12a7 7 0 1 0-14 0c0 5.7 7 12 7 12z"/><circle cx="12" cy="10" r="2.5"/>',
    arrow:'<path d="M5 12h14M13 5l7 7-7 7"/>',
    fb:'<path d="M14 9h3V6h-3a4 4 0 0 0-4 4v2H7v3h3v6h3v-6h3l1-3h-4v-1a1 1 0 0 1 1-1z"/>',
    ig:'<rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.5" cy="6.5" r="1"/>',
    x:'<path d="M4 4l16 16M20 4 4 20"/>',
    yt:'<rect x="2" y="5" width="20" height="14" rx="3"/><path d="M10 9l6 3-6 3z" fill="currentColor" stroke="none"/>'
  };
  function svg(name,cls){return `<svg class="${cls||''}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICON[name]||''}</svg>`;}

  /* ---------------------------------------------------------------------
     DATA
     --------------------------------------------------------------------- */
  const solutions = [
    {icon:'consult',title:'Business Solutions',desc:'End-to-end technology consulting aligned to business outcomes.'},
    {icon:'cloud',title:'Cloud & Virtualization',desc:'Scalable private, public and hybrid cloud environments.'},
    {icon:'shield',title:'Network & Security',desc:'Enterprise networking hardened against modern threats.'},
    {icon:'server',title:'Data Centers',desc:'Design, build and manage resilient data center facilities.'},
    {icon:'backup',title:'Backup & Recovery',desc:'Business continuity with tested disaster recovery plans.'},
    {icon:'chat',title:'Collaboration Solutions',desc:'Unified communications for distributed teams.'},
    {icon:'bolt',title:'Light Current Systems',desc:'CCTV, access control and building management systems.'},
    {icon:'ai',title:'Artificial Intelligence',desc:'Applied AI and machine learning for real operations.'},
    {icon:'erp',title:'ERP Solutions',desc:'Unified planning across finance, supply chain and HR.'},
    {icon:'crm',title:'CRM Solutions',desc:'Customer relationship platforms that scale with growth.'},
    {icon:'dt',title:'Digital Transformation',desc:'Modernization roadmaps from legacy to cloud-native.'},
    {icon:'globe',title:'Managed IT Services',desc:'24/7 monitoring, support and infrastructure management.'}
  ];

  const partners = [
    'Microsoft','Cisco','Dell Technologies','VMware','Huawei','IBM','Oracle','AWS',
    'Google Cloud','Fortinet','Sophos','Lenovo','HPE','Veeam','MikroTik','Red Hat','Odoo','3CX'
  ];
  const partnerDesc = {
    'Microsoft':'Cloud, productivity & AI','Cisco':'Networking & security','Dell Technologies':'Enterprise infrastructure',
    'VMware':'Virtualization platforms','Huawei':'ICT infrastructure','IBM':'Enterprise systems & AI','Oracle':'Database & ERP',
    'AWS':'Public cloud services','Google Cloud':'Cloud & data platforms','Fortinet':'Network security','Sophos':'Endpoint protection',
    'Lenovo':'Enterprise hardware','HPE':'Compute & storage','Veeam':'Backup & recovery','MikroTik':'Networking hardware',
    'Red Hat':'Enterprise open source','Odoo':'Business applications','3CX':'Unified communications'
  };

  const whyChoose = [
    {icon:'innovation',title:'Innovation',desc:'We adopt proven emerging technology ahead of the curve.'},
    {icon:'engineer',title:'Certified Engineers',desc:'Every engagement is staffed by vendor-certified specialists.'},
    {icon:'server',title:'Enterprise Solutions',desc:'Architecture designed for scale, uptime and compliance.'},
    {icon:'support',title:'24/7 Support',desc:'Round-the-clock monitoring and incident response.'},
    {icon:'shield',title:'Security',desc:'Defense-in-depth built into every layer we deliver.'},
    {icon:'cloud',title:'Cloud Expertise',desc:'Deep experience across AWS, Azure, Google Cloud and private cloud.'},
    {icon:'ai',title:'Artificial Intelligence',desc:'Applied AI teams that ship production ML systems.'},
    {icon:'award',title:'Customer Success',desc:'Long-term partnerships measured in renewals, not contracts.'}
  ];

  const services = [
    {icon:'consult',title:'Business Solutions',desc:'Technology strategy and consulting tied directly to business KPIs.'},
    {icon:'ai',title:'Artificial Intelligence',desc:'Computer vision, NLP and predictive systems built for production.'},
    {icon:'bi',title:'Machine Learning',desc:'Custom models trained, deployed and monitored end-to-end.'},
    {icon:'erp',title:'ERP Solutions',desc:'Unified operations across finance, supply chain, HR and procurement.'},
    {icon:'crm',title:'CRM Systems',desc:'Sales, service and marketing platforms built around your customers.'},
    {icon:'cloud',title:'Cloud Infrastructure',desc:'Hybrid and multi-cloud architecture engineered for resilience.'},
    {icon:'server',title:'Cloud Virtualization',desc:'Virtualized compute and storage that scales on demand.'},
    {icon:'shield',title:'Cybersecurity',desc:'Threat detection, response and compliance for regulated industries.'},
    {icon:'network',title:'Network Infrastructure',desc:'Enterprise LAN, WAN and SD-WAN design and deployment.'},
    {icon:'server',title:'Data Centers',desc:'Facility design, build and lifecycle management.'},
    {icon:'backup',title:'Backup & Disaster Recovery',desc:'Tested continuity plans with defined recovery objectives.'},
    {icon:'chat',title:'Collaboration Solutions',desc:'Unified messaging, meetings and workplace tools.'},
    {icon:'voip',title:'IP Telephony',desc:'Enterprise voice systems built on open standards.'},
    {icon:'chat',title:'Video Conferencing',desc:'Room and cloud conferencing systems that just work.'},
    {icon:'bolt',title:'Light Current Systems',desc:'CCTV, access control, fire and building automation.'},
    {icon:'iot',title:'IoT Solutions',desc:'Connected sensors and devices integrated into operations.'},
    {icon:'web',title:'Web Development',desc:'Enterprise web platforms engineered for performance.'},
    {icon:'mobile',title:'Mobile Development',desc:'Native and cross-platform applications for the field and office.'},
    {icon:'bi',title:'Business Intelligence',desc:'Dashboards and reporting that turn data into decisions.'},
    {icon:'bi',title:'Data Analytics',desc:'Data pipelines and analytics built for scale.'},
    {icon:'globe',title:'Managed Services',desc:'Outsourced IT operations backed by defined SLAs.'},
    {icon:'consult',title:'IT Consulting',desc:'Independent advisory on architecture, vendors and roadmaps.'},
    {icon:'dt',title:'Digital Transformation',desc:'Structured modernization from legacy systems to cloud-native.'}
  ];

  const projectCategories = ['All','Government','Banking','Healthcare','Industrial'];
  const projects = [
    {cat:'Government',client:'Ministry of Digital Development',industry:'Government',tech:'Cloud · Cybersecurity',desc:'National data center consolidation and security hardening program.'},
    {cat:'Banking',client:'Nile Commercial Bank',industry:'Banking',tech:'ERP · Cybersecurity',desc:'Core banking infrastructure modernization and SOC deployment.'},
    {cat:'Healthcare',client:'Misurata Scientific Research Centre',industry:'Healthcare',tech:'Networking · Data Center',desc:'Research campus network and laboratory systems integration.'},
    {cat:'Industrial',client:'Delta Manufacturing Group',industry:'Manufacturing',tech:'IoT · BI',desc:'Plant-floor IoT sensors feeding a real-time production dashboard.'},
    {cat:'Government',client:'Riyadh Municipal Authority',industry:'Government',tech:'Light Current · CCTV',desc:'City-wide surveillance and access control rollout.'},
    {cat:'Banking',client:'Gulf Horizon Financial',industry:'Banking',tech:'Cloud · ERP',desc:'Hybrid cloud migration for core financial applications.'},
    {cat:'Healthcare',client:'Al Amal Medical Group',industry:'Healthcare',tech:'Collaboration · Networking',desc:'Multi-site clinical network with unified communications.'},
    {cat:'Industrial',client:'Red Sea Energy Holdings',industry:'Oil & Gas',tech:'Backup & DR · Security',desc:'Business continuity architecture across three regional sites.'},
    {cat:'Government',client:'Ras Al Khaimah Free Zone',industry:'Government',tech:'Managed Services',desc:'Fully outsourced IT operations for a growing free zone authority.'}
  ];

  const industries = [
    {icon:'health',name:'Healthcare'},{icon:'edu',name:'Education'},{icon:'gov',name:'Government'},
    {icon:'bank',name:'Banking'},{icon:'oil',name:'Oil & Gas'},{icon:'retail',name:'Retail'},
    {icon:'factory',name:'Manufacturing'},{icon:'build',name:'Construction'},{icon:'telecom',name:'Telecommunications'},
    {icon:'logistics',name:'Logistics'},{icon:'energy',name:'Energy'},{icon:'hotel',name:'Hospitality'}
  ];

  const boardFirst=['Sherif','Laila','Mostafa','Nourhan','Karim','Dina','Hossam','Yasmin'];
  const boardLast=['Abdel Rahman','El-Naggar','Fathy','Kamal','Basyouni','Rashwan','Zaki','El-Sherbiny'];
  const boardRole=['Chairman of the Board','Vice Chair, Strategy','Board Member, Finance','Board Member, Technology','Board Member, Governance','Board Member, Risk','Board Member, Operations','Independent Board Member'];
  const board = boardFirst.map((f,i)=>({
    name:`${f} ${boardLast[i]}`,
    role:boardRole[i],
    bio:'Brings over two decades of regional leadership experience across enterprise technology and finance.',
    li:'#',email:`board${i+1}@smartsystemit.com`
  }));

  const teamFirst=['Omar','Habiba','Tarek','Salma','Youssef','Rania','Amr','Mariam','Ahmed','Nada','Khaled','Farida','Mahmoud','Aya','Hesham','Reem','Mohamed','Doaa','Sameh','Yara'];
  const teamLast=['Hassan','Adly','Shawky','Fouad','Mansour','El-Deeb','Farouk','Selim','Barakat','Gouda','Sabry','Naguib','Elshamy','Tolba','Ramadan','Aziz','Younis','Hegazy','Mokhtar','Sami'];
  const departments=['Cloud Engineering','Cybersecurity','Networking','ERP Consulting','AI & Data Science','Managed Services','Project Management','Support Engineering'];
  const skillsPool=['Azure','AWS','CCNP','Fortinet NSE','Python','Kubernetes','SAP','Odoo','ISO 27001','PMP'];
  const team = teamFirst.map((f,i)=>{
    const dept=departments[i%departments.length];
    return {
      name:`${f} ${teamLast[i]}`,
      role:dept+' Specialist',
      dept,
      exp:`${3+(i%9)} yrs experience`,
      skills:[skillsPool[i%skillsPool.length],skillsPool[(i+3)%skillsPool.length]],
      email:`${f.toLowerCase()}.${teamLast[i].toLowerCase().replace(' ','')}@smartsystemit.com`,
      badges:2+(i%5)
    };
  });

  const certifications = [
    {name:'Microsoft Solutions Partner',by:'Microsoft',date:'Jan 2026'},
    {name:'Cisco Premier Partner',by:'Cisco',date:'Nov 2025'},
    {name:'AWS Advanced Tier Partner',by:'Amazon Web Services',date:'Aug 2025'},
    {name:'Fortinet Advanced Partner',by:'Fortinet',date:'Jun 2025'},
    {name:'Oracle Gold Partner',by:'Oracle',date:'Mar 2025'},
    {name:'VMware Enterprise Partner',by:'VMware',date:'Feb 2025'},
    {name:'Huawei Authorized Partner',by:'Huawei',date:'Dec 2024'},
    {name:'ISO/IEC 27001 Certified',by:'BSI Group',date:'Oct 2024'}
  ];

  const badges = ['Microsoft Certified','Cisco CCNA','Cisco CCNP','AWS Certified','Azure Certified','Oracle Certified','Huawei Certified','Fortinet NSE','Google Cloud Certified','Dell Technologies Certified','IBM Certified','VMware Certified','SAP Certified','Red Hat Certified','Odoo Certified'];

  const clients = ['Nile Commercial Bank','Gulf Horizon Financial','Red Sea Energy','Delta Manufacturing','Al Amal Medical Group','RAK Free Zone Authority','Riyadh Municipal Authority','Ministry of Digital Development'];
  const testimonials = [
    {q:'Smart System modernized our core infrastructure without a single hour of unplanned downtime.',name:'Ibrahim Naser',role:'CIO, Nile Commercial Bank'},
    {q:'Their engineers hold the certifications they claim, and it shows in the quality of delivery.',name:'Hana Youssef',role:'IT Director, Al Amal Medical Group'},
    {q:'A true partner — responsive, technically deep, and easy to work with across three countries.',name:'Faisal Al-Otaibi',role:'Head of Technology, Gulf Horizon Financial'}
  ];

  const timeline = [
    {year:'2010',title:'Smart System Founded',desc:'Began operations in Cairo, Egypt, delivering networking and infrastructure projects.'},
    {year:'2014',title:'Cybersecurity Practice Launched',desc:'Expanded into managed security services for regional financial institutions.'},
    {year:'2017',title:'Regional Expansion',desc:'Opened operations in Riyadh, Saudi Arabia.'},
    {year:'2019',title:'Cloud & ERP Division',desc:'Formalized cloud infrastructure and ERP consulting practices.'},
    {year:'2021',title:'UAE Office Opened',desc:'Established a Ras Al Khaimah office to serve UAE clients.'},
    {year:'2023',title:'AI & Data Science Team',desc:'Launched a dedicated applied AI and machine learning practice.'},
    {year:'2026',title:'400+ Projects Delivered',desc:'Crossed 400 completed enterprise engagements across three countries.'}
  ];

  const achievements = [
    {icon:'server',count:420,label:'Projects Delivered'},
    {icon:'support',count:180,label:'Happy Clients'},
    {icon:'globe',count:3,label:'Countries'},
    {icon:'engineer',count:65,label:'Certified Engineers'},
    {icon:'award',count:14,label:'Industry Awards'},
    {icon:'bolt',count:16,label:'Years of Operation'}
  ];

  const galleryCats=['All','Office','Events','Training','Projects'];
  const gallery = [
    {cat:'Office',size:'g-h2'},{cat:'Events',size:'g-h1'},{cat:'Training',size:'g-h3'},
    {cat:'Projects',size:'g-h2'},{cat:'Office',size:'g-h1'},{cat:'Events',size:'g-h2'},
    {cat:'Training',size:'g-h1'},{cat:'Projects',size:'g-h3'},{cat:'Office',size:'g-h3'},
    {cat:'Projects',size:'g-h1'},{cat:'Events',size:'g-h3'},{cat:'Training',size:'g-h2'}
  ];

  const faqs = [
    {q:'What industries does Smart System serve?',a:'We deliver enterprise technology for government, banking, healthcare, oil & gas, manufacturing, retail, education and more, with dedicated teams for regulated sectors.'},
    {q:'Do you provide 24/7 support?',a:'Yes. Our managed services division monitors and supports client infrastructure around the clock, backed by defined service-level agreements.'},
    {q:'Which regions do you operate in?',a:'Smart System operates from offices in Egypt, Saudi Arabia and the United Arab Emirates, and delivers projects across the wider region.'},
    {q:'How do I request a proposal?',a:'Submit the sales contact form below with your project details, or email info@smartsystemit.com and our team will respond within one business day.'},
    {q:'Are your engineers certified?',a:'Yes — our team holds certifications across Microsoft, Cisco, AWS, Fortinet, Oracle, VMware, Huawei and other leading vendors.'}
  ];

  const offices = [
    {flag:'🇪🇬',name:'Egypt — Headquarters',addr:'Villa 5, Area 10, Al Lotus, South 90 Street, Fifth Settlement, New Cairo, Egypt',phones:['(+20) 3 5861334','(+20) 1124355530'],email:null},
    {flag:'🇸🇦',name:'Saudi Arabia',addr:'7783 Ibn Katheer, Al Sulaymaniyah, Riyadh, Saudi Arabia',phones:['(+966) 567208122'],email:null},
    {flag:'🇦🇪',name:'United Arab Emirates',addr:'F0B50056 Compass Building, Al Shohada Road, Al Hamra Industrial Zone – FZ, Ras Al Khaimah, United Arab Emirates',phones:[],email:'info@smartsystemit.com'}
  ];

  /* ---------------------------------------------------------------------
     RENDERERS
     --------------------------------------------------------------------- */
  function renderSolutionsMega(){
    document.getElementById('solutionsMegaGrid').innerHTML = solutions.map(s=>`
      <a href="#services" class="mega-item">
        <span class="mega-icon">${svg(s.icon)}</span>
        <span>
          <h4>${s.title}</h4>
          <p>${s.desc}</p>
        </span>
        ${svg('arrow','arrow')}
      </a>`).join('');
  }

  function renderPartnersMega(){
    document.getElementById('partnersMegaGrid').innerHTML = partners.map(p=>`
      <div class="partner-card">
        <div class="logo-ph">${p}</div>
        <span>${partnerDesc[p]||''}</span>
      </div>`).join('');
  }

  function renderWhy(){
    document.getElementById('whyGrid').innerHTML = whyChoose.map((w,i)=>`
      <div class="why-card reveal" style="--i:${i}">
        <div class="why-icon">${svg(w.icon)}</div>
        <h4>${w.title}</h4>
        <p>${w.desc}</p>
      </div>`).join('');
  }

  function renderServices(){
    document.getElementById('servicesGrid').innerHTML = services.map((s,i)=>`
      <div class="service-card glow-hover reveal" style="--i:${i%6}">
        <div class="service-media">
          <span class="ph-label">[ ${s.title} image ]</span>
          <span class="service-icon">${svg(s.icon)}</span>
        </div>
        <div class="service-body">
          <h4>${s.title}</h4>
          <p>${s.desc}</p>
          <a href="#contact" class="service-link">Read More ${svg('arrow')}</a>
        </div>
      </div>`).join('');
  }

  function renderProjects(filter){
    const grid=document.getElementById('projectsGrid');
    const list = (!filter||filter==='All') ? projects : projects.filter(p=>p.cat===filter);
    grid.innerHTML = list.map((p,i)=>`
      <div class="project-card reveal-scale" style="--i:${i}">
        <div class="media"><span class="ph-label">[ ${p.client} project image ]</span></div>
        <div class="overlay">
          <span class="tag">${p.industry}</span>
          <h4>${p.client}</h4>
          <p>${p.tech} — ${p.desc}</p>
          <a href="#contact" class="view-link">View Details ${svg('arrow')}</a>
        </div>
      </div>`).join('');
    revealObserve();
  }

  function renderProjectFilters(){
    const bar=document.getElementById('projectFilters');
    bar.innerHTML = projectCategories.map((c,i)=>`<button class="filter-btn${i===0?' active':''}" data-filter="${c}">${c}</button>`).join('');
    bar.addEventListener('click',e=>{
      const btn=e.target.closest('.filter-btn');
      if(!btn)return;
      bar.querySelectorAll('.filter-btn').forEach(b=>b.classList.remove('active'));
      btn.classList.add('active');
      renderProjects(btn.dataset.filter);
    });
  }

  function renderIndustries(){
    document.getElementById('industriesGrid').innerHTML = industries.map((ind,i)=>`
      <div class="industry-chip reveal" style="--i:${i}">
        ${svg(ind.icon)}
        <span>${ind.name}</span>
      </div>`).join('');
  }

  function renderBoard(){
    document.getElementById('boardGrid').innerHTML = board.map((b,i)=>`
      <div class="person-card reveal" style="--i:${i%4}">
        <div class="person-photo">
          <span class="ph-label">[ Photo ]</span>
          <div class="person-social">
            <a href="${b.li}" aria-label="LinkedIn">${svg('linkedin')}</a>
            <a href="mailto:${b.email}" aria-label="Email">${svg('mail')}</a>
          </div>
        </div>
        <div class="person-info">
          <h4>${b.name}</h4>
          <span class="role">${b.role}</span>
          <p>${b.bio}</p>
        </div>
      </div>`).join('');
  }

  function renderTeam(){
    document.getElementById('teamGrid').innerHTML = team.map((t,i)=>`
      <div class="person-card reveal" style="--i:${i%4}">
        <div class="person-photo">
          <span class="ph-label">[ Photo ]</span>
          <div class="person-social">
            <a href="#" aria-label="LinkedIn">${svg('linkedin')}</a>
            <a href="mailto:${t.email}" aria-label="Email">${svg('mail')}</a>
          </div>
        </div>
        <div class="person-info">
          <h4>${t.name}</h4>
          <span class="role">${t.role}</span>
          <p>${t.dept} · ${t.exp}</p>
          <div class="person-meta">
            ${t.skills.map(s=>`<span>${s}</span>`).join('')}
          </div>
          <span class="badge-count">${t.badges} certification badges</span>
        </div>
      </div>`).join('');
  }

  function renderCerts(){
    document.getElementById('certsGrid').innerHTML = certifications.map((c,i)=>`
      <div class="cert-card reveal" style="--i:${i%4}">
        <div class="cert-media">[ Certificate image ]</div>
        <div class="cert-body">
          <h4>${c.name}</h4>
          <span class="issuer">Issued by ${c.by}</span>
          <span class="date">${c.date}</span>
          <a href="#" class="cert-link">View Certificate →</a>
        </div>
      </div>`).join('');
  }

  function renderBadges(){
    document.getElementById('badgesWall').innerHTML = badges.map(b=>`
      <div class="badge-pill"><span class="dot"></span>${b}</div>`).join('');
  }

  function renderPartnerTrack(){
    const html = [...partners,...partners].map(p=>`<div class="logo-ph">${p}</div>`).join('');
    document.getElementById('partnersTrack').innerHTML = html;
  }

  function renderClients(){
    const html = [...clients,...clients].map(c=>`<div class="logo-ph">${c}</div>`).join('');
    document.getElementById('clientsTrack').innerHTML = html;
    document.getElementById('testimonialsGrid').innerHTML = testimonials.map(t=>`
      <div class="testimonial-card reveal">
        <div class="stars">${'★★★★★'.split('').map(()=>`<svg viewBox="0 0 24 24"><path d="M12 2l3 7h7l-5.5 4.2L18.5 21 12 16.8 5.5 21l2-7.8L2 9h7z"/></svg>`).join('')}</div>
        <p>"${t.q}"</p>
        <div class="testimonial-person">
          <div class="testimonial-avatar"></div>
          <div><b>${t.name}</b><span>${t.role}</span></div>
        </div>
      </div>`).join('');
  }

  function renderTimeline(){
    document.getElementById('timelineList').innerHTML = timeline.map(t=>`
      <div class="timeline-item reveal">
        <span class="timeline-dot"></span>
        <span class="year">${t.year}</span>
        <h4>${t.title}</h4>
        <p>${t.desc}</p>
      </div>`).join('');
  }

  function renderAchievements(){
    document.getElementById('achieveGrid').innerHTML = achievements.map(a=>`
      <div class="achieve-item">
        ${svg(a.icon)}
        <span class="count" data-count="${a.count}">0</span>
        <label>${a.label}</label>
      </div>`).join('');
  }

  function renderGallery(filter){
    const grid=document.getElementById('galleryGrid');
    const list = (!filter||filter==='All') ? gallery : gallery.filter(g=>g.cat===filter);
    grid.innerHTML = list.map(g=>`<div class="gallery-item ${g.size}">[ ${g.cat} photo ]</div>`).join('');
  }
  function renderGalleryTabs(){
    const tabs=document.getElementById('galleryTabs');
    tabs.innerHTML = galleryCats.map((c,i)=>`<button class="filter-btn${i===0?' active':''}" data-cat="${c}">${c}</button>`).join('');
    tabs.addEventListener('click',e=>{
      const btn=e.target.closest('.filter-btn');
      if(!btn)return;
      tabs.querySelectorAll('.filter-btn').forEach(b=>b.classList.remove('active'));
      btn.classList.add('active');
      renderGallery(btn.dataset.cat);
    });
  }

  function renderFaq(){
    const list=document.getElementById('faqList');
    list.innerHTML = faqs.map(f=>`
      <div class="faq-item">
        <button class="faq-question"><span>${f.q}</span><span class="plus"></span></button>
        <div class="faq-answer"><p>${f.a}</p></div>
      </div>`).join('');
    list.addEventListener('click',e=>{
      const q=e.target.closest('.faq-question');
      if(!q)return;
      const item=q.parentElement;
      const answer=item.querySelector('.faq-answer');
      const willOpen=!item.classList.contains('open');
      list.querySelectorAll('.faq-item').forEach(it=>{
        it.classList.remove('open');
        it.querySelector('.faq-answer').style.maxHeight=null;
      });
      if(willOpen){
        item.classList.add('open');
        answer.style.maxHeight = answer.scrollHeight+'px';
      }
    });
  }

  function renderOffices(){
    document.getElementById('officeCards').innerHTML = offices.map(o=>`
      <div class="office-card reveal">
        <span class="office-flag">${o.flag}</span>
        <div>
          <h4>${svg('pin')}${o.name}</h4>
          <address>${o.addr}</address>
          ${o.phones.map(p=>`<span class="contact-line">${svg('phone')}${p}</span>`).join('')}
          ${o.email?`<span class="contact-line">${svg('mail')}${o.email}</span>`:''}
        </div>
      </div>`).join('');
  }

  function renderFooterSocial(){
    const icons=['linkedin','fb','ig','x','yt'];
    document.getElementById('footerSocial').innerHTML = icons.map(i=>`<a href="#" aria-label="${i}">${svg(i)}</a>`).join('');
  }

  /* ---------------------------------------------------------------------
     HERO NETWORK ANIMATION (SVG nodes + connecting lines)
     --------------------------------------------------------------------- */
  function initHeroNetwork(){
    const svgEl = document.getElementById('hero-network');
    if(!svgEl) return;
    const NS='http://www.w3.org/2000/svg';
    let w=svgEl.clientWidth, h=svgEl.clientHeight;
    svgEl.setAttribute('viewBox',`0 0 ${w} ${h}`);
    const count = w<700 ? 16 : 34;
    const nodes = Array.from({length:count},()=>({
      x:Math.random()*w, y:Math.random()*h,
      vx:(Math.random()-.5)*.25, vy:(Math.random()-.5)*.25
    }));
    const lineGroup=document.createElementNS(NS,'g');
    const dotGroup=document.createElementNS(NS,'g');
    svgEl.appendChild(lineGroup);
    svgEl.appendChild(dotGroup);
    const dots = nodes.map(()=>{
      const c=document.createElementNS(NS,'circle');
      c.setAttribute('r','1.8');
      c.setAttribute('fill','rgba(62,210,238,.55)');
      dotGroup.appendChild(c);
      return c;
    });

    function frame(){
      lineGroup.innerHTML='';
      nodes.forEach(n=>{
        n.x+=n.vx; n.y+=n.vy;
        if(n.x<0||n.x>w)n.vx*=-1;
        if(n.y<0||n.y>h)n.vy*=-1;
      });
      for(let i=0;i<nodes.length;i++){
        dots[i].setAttribute('cx',nodes[i].x);
        dots[i].setAttribute('cy',nodes[i].y);
        for(let j=i+1;j<nodes.length;j++){
          const dx=nodes[i].x-nodes[j].x, dy=nodes[i].y-nodes[j].y;
          const dist=Math.sqrt(dx*dx+dy*dy);
          if(dist<150){
            const line=document.createElementNS(NS,'line');
            line.setAttribute('x1',nodes[i].x);line.setAttribute('y1',nodes[i].y);
            line.setAttribute('x2',nodes[j].x);line.setAttribute('y2',nodes[j].y);
            line.setAttribute('stroke','rgba(46,150,255,'+(0.22*(1-dist/150))+')');
            line.setAttribute('stroke-width','1');
            lineGroup.appendChild(line);
          }
        }
      }
      requestAnimationFrame(frame);
    }
    if(!window.matchMedia('(prefers-reduced-motion: reduce)').matches){
      requestAnimationFrame(frame);
    }
    window.addEventListener('resize',()=>{
      w=svgEl.clientWidth; h=svgEl.clientHeight;
      svgEl.setAttribute('viewBox',`0 0 ${w} ${h}`);
    });
  }

  /* ---------------------------------------------------------------------
     HEADER / MOBILE NAV / SCROLL BEHAVIOR
     --------------------------------------------------------------------- */
  function initHeader(){
    const header=document.getElementById('siteHeader');
    const onScroll=()=>{
      header.classList.toggle('scrolled', window.scrollY>40);
      const backTop=document.getElementById('backToTop');
      backTop.classList.toggle('visible', window.scrollY>500);
    };
    window.addEventListener('scroll',onScroll,{passive:true});
    onScroll();

    const toggle=document.getElementById('menuToggle');
    const mobileNav=document.getElementById('mobileNav');
    toggle.addEventListener('click',()=>{
      const open=mobileNav.classList.toggle('open');
      toggle.setAttribute('aria-expanded',open);
      toggle.classList.toggle('active',open);
    });
    mobileNav.querySelectorAll('a').forEach(a=>a.addEventListener('click',()=>{
      mobileNav.classList.remove('open');
      toggle.setAttribute('aria-expanded','false');
    }));

    document.getElementById('backToTop').addEventListener('click',()=>{
      window.scrollTo({top:0,behavior:'smooth'});
    });
  }

  /* ---------------------------------------------------------------------
     SCROLL REVEAL
     --------------------------------------------------------------------- */
  let revealIO;
  function revealObserve(){
    const items=document.querySelectorAll('.reveal:not(.visible), .reveal-scale:not(.visible)');
    items.forEach(el=>revealIO.observe(el));
  }
  function initReveal(){
    revealIO = new IntersectionObserver(entries=>{
      entries.forEach(entry=>{
        if(entry.isIntersecting){
          entry.target.classList.add('visible');
          revealIO.unobserve(entry.target);
        }
      });
    },{threshold:.15,rootMargin:'0px 0px -60px 0px'});
    revealObserve();
  }

  /* ---------------------------------------------------------------------
     ANIMATED COUNTERS
     --------------------------------------------------------------------- */
  function initCounters(){
    const counters=document.querySelectorAll('[data-count]');
    const io=new IntersectionObserver(entries=>{
      entries.forEach(entry=>{
        if(!entry.isIntersecting)return;
        const el=entry.target;
        const target=parseInt(el.dataset.count,10);
        const dur=1400;
        const start=performance.now();
        function tick(now){
          const p=Math.min((now-start)/dur,1);
          const eased=1-Math.pow(1-p,3);
          el.textContent=Math.floor(eased*target).toLocaleString();
          if(p<1) requestAnimationFrame(tick);
          else { el.textContent=target.toLocaleString(); el.classList.add('counted'); }
        }
        requestAnimationFrame(tick);
        io.unobserve(el);
      });
    },{threshold:.4});
    counters.forEach(c=>io.observe(c));
  }

  /* ---------------------------------------------------------------------
     RIPPLE EFFECT ON BUTTONS
     --------------------------------------------------------------------- */
  function initRipple(){
    document.addEventListener('click',e=>{
      const btn=e.target.closest('.btn');
      if(!btn)return;
      const rect=btn.getBoundingClientRect();
      const ripple=document.createElement('span');
      const size=Math.max(rect.width,rect.height);
      ripple.className='ripple-effect';
      ripple.style.width=ripple.style.height=size+'px';
      ripple.style.left=(e.clientX-rect.left-size/2)+'px';
      ripple.style.top=(e.clientY-rect.top-size/2)+'px';
      btn.appendChild(ripple);
      setTimeout(()=>ripple.remove(),650);
    });
  }

  /* ---------------------------------------------------------------------
     MOUSE PARALLAX (hero floating shapes)
     --------------------------------------------------------------------- */
  function initParallax(){
    const hero=document.querySelector('.hero');
    if(!hero) return;
    const shapes=hero.querySelectorAll('.floating-shape');
    hero.addEventListener('mousemove',e=>{
      const {left,top,width,height}=hero.getBoundingClientRect();
      const x=(e.clientX-left)/width-.5, y=(e.clientY-top)/height-.5;
      shapes.forEach((s,i)=>{
        const depth=(i+1)*10;
        s.style.transform=`translate(${x*depth}px, ${y*depth}px)`;
      });
    });
  }

  /* ---------------------------------------------------------------------
     CONTACT FORM VALIDATION
     --------------------------------------------------------------------- */
  function initForm(){
    const form=document.getElementById('salesForm');
    if(!form)return;
    const status=document.getElementById('formStatus');
    const submitBtn=document.getElementById('submitBtn');

    function setError(group,msg){
      group.classList.toggle('error',!!msg);
      const err=group.querySelector('.field-error');
      if(err) err.textContent=msg||'';
    }

    function validate(){
      let valid=true;
      form.querySelectorAll('.form-group,.form-checkbox').forEach(group=>{
        const field=group.querySelector('input,textarea,select');
        if(!field || !field.required) return;
        let msg='';
        if(field.type==='checkbox' && !field.checked) msg='Please accept the Privacy Policy to continue.';
        else if(field.type!=='checkbox' && !field.value.trim()) msg='This field is required.';
        else if(field.type==='email' && field.value && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(field.value)) msg='Enter a valid email address.';
        else if(field.type==='tel' && field.value && field.value.replace(/\D/g,'').length<7) msg='Enter a valid phone number.';
        if(msg){valid=false;}
        setError(group,msg);
      });
      return valid;
    }

    form.addEventListener('submit',e=>{
      e.preventDefault();
      status.textContent='';
      status.className='form-status';
      if(!validate()){
        status.textContent='Please correct the highlighted fields.';
        status.classList.add('error-msg');
        return;
      }
      submitBtn.classList.add('loading');
      submitBtn.disabled=true;
      setTimeout(()=>{
        submitBtn.classList.remove('loading');
        submitBtn.disabled=false;
        status.textContent='Message sent — our sales team will respond within one business day.';
        status.classList.add('success');
        form.reset();
      },1400);
    });

    const newsletter=document.getElementById('newsletterForm');
    if(newsletter){
      newsletter.addEventListener('submit',e=>{
        e.preventDefault();
        const input=newsletter.querySelector('input');
        input.value='Subscribed ✓';
        setTimeout(()=>{input.value='';},2200);
      });
    }
  }

  /* ---------------------------------------------------------------------
     PAGE LOADER
     --------------------------------------------------------------------- */
  function initLoader(){
    window.addEventListener('load',()=>{
      const loader=document.getElementById('pageLoader');
      setTimeout(()=>loader.classList.add('hidden'),350);
    });
  }

  /* ---------------------------------------------------------------------
     INIT
     --------------------------------------------------------------------- */
  document.addEventListener('DOMContentLoaded',()=>{
    document.getElementById('year').textContent=new Date().getFullYear();

    initReveal();

    renderSolutionsMega();
    renderPartnersMega();
    renderWhy();
    renderServices();
    renderProjectFilters();
    renderProjects('All');
    renderIndustries();
    renderBoard();
    renderTeam();
    renderCerts();
    renderBadges();
    renderPartnerTrack();
    renderClients();
    renderTimeline();
    renderAchievements();
    renderGalleryTabs();
    renderGallery('All');
    renderFaq();
    renderOffices();
    renderFooterSocial();

    revealObserve();

    initHeroNetwork();
    initHeader();
    initCounters();
    initRipple();
    initParallax();
    initForm();
    initLoader();
  });
})();