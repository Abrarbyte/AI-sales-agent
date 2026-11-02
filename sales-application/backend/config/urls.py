"""
URL configuration for config project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.1/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path

from common.exports import PipelineExportView
from common.health import health

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/health/', health, name='health'),
    path('api/auth/', include('accounts.urls')),
    path('api/attendance/', include('attendance.urls')),
    path('api/crm/', include('crm.urls')),
    path('api/visits/', include('visits.urls')),
    path('api/analytics/', include('analytics.urls')),
    path('api/notifications/', include('notifications.urls')),
    path('api/export/pipeline.xlsx', PipelineExportView.as_view(), name='export-pipeline'),
    path('api/delivery/', include('delivery.urls')),
    path('api/allowances/', include('allowances.urls')),
    path('api/app/', include('releases.urls')),
]

# Visit photographs, served by Django itself while developing so the phone can
# load them back. `static()` returns nothing unless DEBUG, and a deployment
# serves MEDIA_ROOT from the web server instead.
urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
